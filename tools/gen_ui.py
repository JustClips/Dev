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


def autoscale(compact=None):
    """compact: extra factor on phones (Ui.rescale reads the CompactScale attribute)."""
    return node("AutoScale", "UIScale", {"Scale": 1}, attrs={"CompactScale": compact} if compact else None)


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


MIN_TS = 16  # smallest text size anywhere (Dev: small labels and badge numbers were unreadable)
# The smallest a fitted label may shrink to. UITextSizeConstraint counts real screen pixels
# (UIScale doesn't change it), so a high minimum cuts words off on small phones ("Upgra").
MIN_FIT = 7


def readable(p, children):
    """Keeps a label readable: never below MIN_TS. A label that had to grow shrinks back to
    fit its box (TextScaled + Fit) instead of spilling out. Returns extra children."""
    for c in children or []:
        if c and c.get("name") == "Fit":
            fit = c["properties"]
            fit["MaxTextSize"] = max(fit.get("MaxTextSize", MIN_TS), MIN_TS)
            fit["MinTextSize"] = min(fit.get("MinTextSize", MIN_FIT), MIN_FIT)
            p["TextSize"] = max(p["TextSize"], MIN_TS)
            return []
    if p["TextSize"] >= MIN_TS:
        return []
    p["TextSize"] = MIN_TS
    if p.get("AutomaticSize") or p.get("TextScaled"):
        return []
    p["TextScaled"] = True
    return [node("Fit", "UITextSizeConstraint", {"MaxTextSize": MIN_TS, "MinTextSize": MIN_FIT})]


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
    kids += readable(p, children)
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
    """Count badge: a red square with a white outline and a big white number (Dev wanted the
    square back, with a number you can read). Controllers set it with Ui.setBadge, which
    widens it for 2-3 digits and pops it when the count goes up."""
    # Dev, 2026-10-31: every badge is a red "!" (Ui.setBadge), upright, crisp: a flat red
    # square with a dark outline and a plain white "!" (the thin white ring and text
    # outline looked blurry at phone size).
    return frame("Badge", U(0, px, 0, px), U(1, 6, 0, -10), (1, 0), bg=BADGE_RED, Visible=False, ZIndex=z, children=[
        node("Stroke", "UIStroke", {"Color": INK, "Thickness": 2.5, "ApplyStrokeMode": "Border", "LineJoinMode": "Miter"}),
        text("Label", "!", U(1, 0, 1, 2), U(0.5, 0, 0.5, 0), (0.5, 0.5), ts=px - 4, display=True, ZIndex=z + 1),
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


def window(w, h, title, ico, children, header=HEADER, popup=False, scale=1.0, size=None):
    """Modal window: white stud body, coloured stud header strip, red X top-right. Always
    WIN_W x WIN_H (or POP_W x POP_H for popups); smaller layouts are centred inside."""
    W, H = (POP_W, POP_H) if popup else (WIN_W, WIN_H)
    if size:
        # Fitted to its content (Dev, 2026-10-31: Gifts, Codes, Rebirth were too big and empty).
        W, H = size
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
        text("Label", label, U(1, -4, 0, 20), U(0.5, 0, 1, -4), (0.5, 1), ts=17, display=True, stroke=2.5,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 17, "MinTextSize": 7})]),
        badge(),
    ])


def pill(name, label, ico, color, order):
    return button(name, U(0, 136, 0, 52), color=color, label=label, ts=21, ico=ico, ico_px=40, LayoutOrder=order)


def hot_slot(name, key, ico, label, order):
    """Roblox-backpack style slot: dark see-through square, number top-left, big icon."""
    return button(name, U(0, 84, 0, 84), color="#0B0E1E", stroke=3, BackgroundTransparency=0.35, LayoutOrder=order, children=[
        icon("Icon", ico, 70, U(0.5, 0, 0.5, -6), (0.5, 0.5)),
        text("Name", label, U(1, -6, 0, 20), U(0.5, 0, 1, -2), (0.5, 1), ts=16, color=WHITE, display=True, stroke=2, ZIndex=4),
        frame("Key", U(0, 22, 0, 22), U(0, 3, 0, 2), ZIndex=4, children=[
            text("Label", key, U(1, 0, 1, 0), ts=16, display=True, stroke=2, xa="Left", ya="Top", ZIndex=5),
        ]),
    ])


def item_slot(name, key, order):
    """A hotbar slot for a pet, a stack of eggs or a potion: the model (or icon), its name
    in its rarity colour, a count for stacks, and its key number."""
    slot = hot_slot(name, key, "Egg", "", order)
    slot["properties"]["Visible"] = False
    kids = slot["children"]
    for k in kids:
        if k and k.get("name") == "Name":
            k["properties"].update(TextScaled=True, TextWrapped=False)
            k["children"] = [c for c in k.get("children", []) if c.get("name") != "Fit"] + [
                node("Fit", "UITextSizeConstraint", {"MaxTextSize": 16, "MinTextSize": 7})]
        if k and k.get("name") == "Icon":
            k["properties"]["Visible"] = False
    kids.insert(0, node("Viewport", "ViewportFrame", base(U(1, -8, 1, -24), U(0.5, 0, 0, 3), (0.5, 0), BackgroundTransparency=1,
                                                          Ambient="#C8D0E8", LightColor=WHITE, LightDirection=[-1, -1, -1], ZIndex=2)))
    kids.append(text("Count", "", U(0, 40, 0, 20), U(1, -4, 0, 2), (1, 0), ts=16, display=True, stroke=2, xa="Right", ZIndex=5,
                     Visible=False))
    return slot


def zone_row(zone_id, title, order):
    return button("Zone_" + zone_id, U(1, 0, 0, 50), color=HEADER, stroke=3, LayoutOrder=order, children=[
        icon("Icon", "Zones", 36, U(0, 8, 0.5, 0), (0, 0.5)),
        text("Name", title, U(0.6, -50, 1, 0), U(0, 52, 0, 0), ts=18, display=True, stroke=2.5, xa="Left"),
        text("Price", "", U(0.4, -10, 1, 0), U(1, -10, 0, 0), (1, 0), ts=16, heavy=True, stroke=2.5, xa="Right"),
    ])




def auto_toggle(name, label, ico, order):
    """Auto Sweep / Auto Sell switch: icon, name, and an ON/OFF tag (HudController colours it)."""
    return button(name, U(0, 230, 0, 50), color=BG, ico=ico, ico_px=40, LayoutOrder=order, Visible=False, dark="#9AA3B8", children=[
        text("Label", label, U(1, -114, 1, -8), U(0, 52, 0, 4), ts=20, display=True, stroke=2.5, xa="Left", TextScaled=True,
             TextWrapped=False, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 20, "MinTextSize": 10})]),
        frame("State", U(0, 52, 0, 30), U(1, -8, 0.5, 0), (1, 0.5), bg=MUTED, ZIndex=3, children=[
            border(INK, 2),
            text("Label", "OFF", U(1, 0, 1, 0), ts=17, display=True, stroke=2, ZIndex=4),
        ]),
    ])


def hud():
    # Rebirth tile shows how close the next rebirth is ("60%", RebirthController), like
    # Dev's reference.
    rebirth_tile = rail_tile("RebirthButton", "Rebirth", "Rebirth", REBIRTH, 4)
    rebirth_tile["children"].append(
        text("Progress", "0%", U(1, -4, 0, 24), U(0.5, 0, 0, 1), (0.5, 0), ts=21, color=WHITE, display=True, stroke=3, ZIndex=5,
             Visible=False))
    # Phones: tiles 26% smaller (Dev, 2026-10-31: the left side was too full to see where
    # you walk), same spot.
    rail = frame("Rail", U(0, 180, 0, 304), U(0, 14, 0.5, -30), (0, 0.5), children=[
        autoscale(compact=0.74),
        node("Layout", "UIGridLayout", {"CellSize": U(0, 84, 0, 84), "CellPadding": U(0, 12, 0, 26), "SortOrder": "LayoutOrder"}),
        rail_tile("ShopButton", "Shop", "Shop", PREMIUM, 1),
        rail_tile("IndexButton", "Index", "Index", "#4CC3FF", 2),
        rail_tile("UpgradesButton", "Upgrades", "Upgrade", "#FF9A3C", 3),
        rebirth_tile,
        rail_tile("RewardsButton", "Daily", "Daily", "#FF5FA2", 5),
        rail_tile("GiftsButton", "Gifts", "Gift", "#3DDC5A", 6),
    ])
    pills = frame("Pills", U(0, 432, 0, 52), U(0.5, 0, 0, 6), (0.5, 0), children=[
        autoscale(), hlist(12),
        pill("BaseButton", "Base", "Base", PILL_BASE, 1),
        pill("SellButton", "Sell", "Sell", PILL_SELL, 2),
        pill("ZonesButton", "Zones", "Zones", PILL_ZONES, 3),
        # Free group reward (GroupRewardController shows it until it's claimed).
        button("FreeButton", U(0, 136, 0, 52), color="#FFB020", label="Free", ts=21, ico="Gift", ico_px=40, LayoutOrder=4,
               Visible=False, children=[badge()]),
    ])
    # Fixed height: a UIListLayout directly in a plate would also stack the Studs image.
    picker = plate("ZonePicker", U(0, 330, 0, 348), U(0.5, 0, 0, 66), (0.5, 0), SURFACE, Visible=False, ZIndex=6,
                   children=[
                       autoscale(),
                       frame("List", U(1, -20, 1, -20), U(0, 10, 0, 10), children=[
                           vlist(8),
                           text("Title", "Teleport", U(1, 0, 0, 28), ts=24, color=INK, display=True, LayoutOrder=0),
                           zone_row("Landing", "Backyard", 1),
                           zone_row("Crater", "Park", 2),
                           zone_row("DarkSide", "Beach", 3),
                           zone_row("Mars", "City", 4),
                           zone_row("Europa", "Snowy Peaks", 5),
                       ]),
                   ])
    # World Cleaned: the star icon on the left, then one thick bar with the title and the %
    # written inside it (big enough to read on a phone). Turns orange for the Egg Rain
    # countdown and the rain itself (HudController).
    moon = frame("MoonPanel", U(0, 360, 0, 46), U(0.5, 0, 0, 66), (0.5, 0), children=[
        autoscale(),
        frame("Bar", U(1, -24, 0, 34), U(1, 0, 0.5, 0), (1, 0.5), bg=BG, ClipsDescendants=False, children=[
            border(INK, 3),
            frame("Fill", U(0.3, 0, 1, 0), bg=ACCENT, ClipsDescendants=True, children=[
                node("Shade", "UIGradient", {"Color": {"keypoints": [[0, WHITE], [1, "#B8C4D8"]]}, "Rotation": 90}),
                frame("Shine", U(0, 40, 1, 0), U(-0.2, 0, 0, 0), bg=WHITE, BackgroundTransparency=0.55, Rotation=0, ZIndex=3),
            ]),
            node("Ticks", "Frame", base(U(1, 0, 1, 0), BackgroundTransparency=1, ZIndex=4), [
                frame(f"Tick{i}", U(0, 2, 1, 0), U(i / 4, -1, 0, 0), bg=INK, BackgroundTransparency=0.6, ZIndex=4)
                for i in (1, 2, 3)
            ]),
        ]),
        icon("Icon", "Star", 46, U(0, 0, 0.5, 0), (0, 0.5), ZIndex=6),
        text("Title", "WORLD CLEANED", U(1, -130, 0, 34), U(0, 50, 0.5, 0), (0, 0.5), ts=18, color=WHITE, display=True, xa="Left",
             stroke=2.5, ZIndex=5),
        text("Value", "0%", U(0, 80, 0, 34), U(1, -10, 0.5, 0), (1, 0.5), ts=20, color=WHITE, display=True, xa="Right", stroke=2.5,
             ZIndex=5),
        # Kept for older code paths that set one line of text.
        text("Label", "", U(1, -58, 0, 16), U(0, 52, 0, 4), ts=13, display=True, Visible=False),
    ])
    # Active boosts (server luck, 2x cash): chips stacked in the bottom-right corner.
    # Phones move them to the top right (HudController), clear of the jump button.
    # Boost chips: no box, just a small icon and "2x 14:52". Hover (or tap) shows what the
    # boost does in BoostTip.
    boosts = frame("Boosts", U(0, 300, 0, 260), U(1, -14, 1, -14), (1, 1), children=[
        autoscale(), vlist(4, "Right", "Bottom"),
        node("Template", "TextButton", base(U(0, 0, 0, 42), BackgroundTransparency=1, Text="", AutomaticSize="X",
                                           AutoButtonColor=False, Visible=False, ZIndex=2),
             [hlist(6, "Right"),
              icon("Icon", "Luck", 40, LayoutOrder=1),
              text("Label", "", U(0, 0, 1, 0), ts=26, display=True, stroke=3, AutomaticSize="X", TextWrapped=False,
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
    # Server-wide news (someone bought a server boost): a slim strip under the World
    # Cleaned bar (HudController places it), out of the middle of the screen.
    announcement = plate("Announcement", U(0, 0, 0, 44), U(0.5, 0, 0, 120), (0.5, 0), BG, stud=0.5, AutomaticSize="X", Visible=False,
                         children=[
                             autoscale(), padding(16, 16, 0),
                             text("Text", "", U(0, 0, 1, 0), ts=24, color=PREMIUM, display=True, stroke=2.5, AutomaticSize="X", TextWrapped=False),
                         ])
    # Wallet: two dark strips with big outlined numbers (readable on a phone at 60% size).
    # Cash: coin, amount, income under it, green + for the cash shop. Bag: leaf bag icon and
    # a thick bar with "310 / 500" inside; it turns red with FULL when the bag is full.
    # Wallet (Dev, 2026-10-31, from a reference): rebirth count, cash with its +, the bag bar. One icon column on the left, one text column,
    # the same 34 px + buttons on the right, thin lines between rows.
    def row(name, y, h, children, line=True):
        kids = list(children)
        if line:
            kids.append(frame("Line", U(1, -16, 0, 2), U(0, 8, 0, 0), bg="#3A404D"))
        return frame(name, U(1, 0, 0, h), U(0, 0, 0, y), children=kids)

    def plus(name, color=SUCCESS):
        return button(name, U(0, 34, 0, 34), U(1, -8, 0.5, 0), (1, 0.5), color=color, label="+", ts=28, stroke=3)

    # The Friend Boost moved to the boost chips at the bottom right (Dev, 2026-10-31).
    wallet = plate("Wallet", U(0, 264, 0, 130), U(0, 14, 1, -14), (0, 1), tint=BG, stroke=3, children=[
        autoscale(compact=0.85),
        row("RebirthRow", 4, 34, [
            icon("Icon", "Rebirth", 30, U(0, 26, 0.5, 0), (0.5, 0.5)),
            text("Value", "0 Rebirths", U(1, -60, 1, 0), U(0, 50, 0, 0), ts=19, color="#E2B6FF", display=True, xa="Left",
                 stroke=2.5),
        ], line=False),
        row("CashPanel", 38, 52, [
            icon("Icon", "Cash", 42, U(0, 26, 0.5, 0), (0.5, 0.5)),
            text("Cash", "$0", U(1, -100, 0, 28), U(0, 50, 0, 5), ts=28, color=WHITE, display=True, xa="Left", stroke=2.5,
                 TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 28, "MinTextSize": 12})]),
            text("Income", "+$0/s", U(1, -100, 0, 16), U(0, 50, 0, 32), ts=16, color=ACCENT, display=True, xa="Left", stroke=2),
            plus("PlusButton"),
        ]),
        row("BackpackPanel", 90, 38, [
            icon("Icon", "Backpack", 32, U(0, 26, 0.5, 0), (0.5, 0.5), ZIndex=4),
            frame("Bar", U(1, -58, 0, 24), U(0, 50, 0.5, 0), (0, 0.5), bg="#14171D", children=[
                border(INK, 2),
                frame("Fill", U(0.2, 0, 1, 0), bg="#FF9A3C", children=[
                    node("Shade", "UIGradient", {"Color": {"keypoints": [[0, WHITE], [1, "#C8CEDA"]]}, "Rotation": 90}),
                ]),
                text("Amount", "0 / 50", U(1, -12, 1, 0), U(0, 6, 0, 0), ts=16, display=True, stroke=2.5, xa="Left", ZIndex=3),
            ]),
            frame("Full", U(0, 50, 0, 24), U(1, -10, 0.5, 0), (1, 0.5), Visible=False, ZIndex=4, children=[
                text("Label", "FULL", U(1, 0, 1, 0), ts=16, display=True, stroke=2.5, ZIndex=5),
            ]),
        ]),
    ])
    right = frame("Right", U(0, 230, 0, 240), U(1, -14, 0.5, 0), (1, 0.5), children=[
        autoscale(), vlist(10, "Right", "Center"),
        auto_toggle("AutoButton", "Auto Sweep", "Auto", 3),
        auto_toggle("AutoSellButton", "Auto Sell", "Sell", 4),
    ])
    # No Sweep button on phones: holding a finger on the screen sweeps (SweepController,
    # Dev 2026-10-30).
    # Own hotbar (the default Roblox backpack is hidden), Roblox-tool style: 1 = tool,
    # 2 = car, 3-8 = pets / egg stacks / potions (pinned ones first, HotbarController), then
    # the bag button (B) and, while you carry an egg on your head, Drop egg (G).
    bag = hot_slot("BagSlot", "B", "Backpack", "Bag", 20)
    bag["children"].append(badge())
    drop = hot_slot("DropSlot", "G", "Egg", "Drop egg", 21)
    drop["properties"]["BackgroundColor3"] = DANGER
    drop["properties"]["BackgroundTransparency"] = 0.15
    drop["properties"]["Visible"] = False
    items = [item_slot(f"Item{i}", str(i + 2), 10 + i) for i in range(1, 7)]
    hotbar = frame("Hotbar", U(0, 900, 0, 88), U(0.5, 0, 1, -12), (0.5, 1), children=[
        autoscale(0.84), hlist(8, "Center", "Bottom"),
        # Controller hints (HotbarController): LB / RB step through the slots.
        node("PadLB", "ImageLabel", base(U(0, 44, 0, 44), BackgroundTransparency=1, Image="", ScaleType="Fit", Visible=False,
                                         LayoutOrder=0, ZIndex=4)),
        hot_slot("ToolSlot", "1", "Tool", "Toothbrush", 1),
        hot_slot("CarSlot", "2", "Vehicle", "No car", 2),
    ] + items + [
        node("PadRB", "ImageLabel", base(U(0, 44, 0, 44), BackgroundTransparency=1, Image="", ScaleType="Fit", Visible=False,
                                         LayoutOrder=19, ZIndex=4)),
        bag,
        drop,
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
        frame("Done", U(1, 0, 1, 0), bg=SUCCESS, BackgroundTransparency=1, Visible=False, ZIndex=5, children=[
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
    # Sweep combo (Dev, 2026-10-31, from a reference shot): a big blue "x553" with COMBO under
    # it next to your character, popping on every sweep, a thin bar for the time left and the
    # cash multiplier. Milestones (x100, x250, x500...) burst a "GREAT!" with rays on the
    # other side (ComboBurst). The pop runs on Body.Pop so it doesn't fight AutoScale.
    def blue():
        return node("Shade", "UIGradient", {"Color": {"keypoints": [[0, "#BDEBFF"], [0.5, "#5BB8FF"], [1, "#2A6FE8"]]}, "Rotation": 90})
    # Named ComboCounter: the old "Combo" frame lived on in synced Studio places (Dev saw both).
    combo = frame("ComboCounter", U(0, 280, 0, 120), U(0.5, 170, 0.5, -50), (0, 0.5), Visible=False, Rotation=-5, children=[
        autoscale(0.8),
        frame("Body", U(1, 0, 1, 0), children=[
            node("Pop", "UIScale", {"Scale": 1}),
            text("Label", "x0", U(1, 0, 0, 70), U(0, 0, 0, 0), ts=68, color=WHITE, display=True, stroke=5, xa="Left",
                 TextWrapped=False, children=[blue()]),
            text("Title", "COMBO", U(0, 140, 0, 28), U(0, 10, 0, 64), ts=28, color=WHITE, display=True, stroke=3.5, xa="Left",
                 TextWrapped=False),
            frame("Bar", U(0, 130, 0, 8), U(0, 10, 0, 100), bg="#0B0E1E", children=[
                border(INK, 2),
                frame("Fill", U(1, 0, 1, 0), bg="#5BB8FF"),
            ]),
            text("Mult", "Cash x1.0", U(0, 120, 0, 22), U(0, 150, 0, 93), ts=18, color=PREMIUM, display=True, stroke=2.5,
                 xa="Left", TextWrapped=False),
        ]),
    ])
    burst = frame("ComboBurst", U(0, 320, 0, 160), U(0.5, -90, 0.5, -70), (1, 0.5), Visible=False, Rotation=-8, children=[
        autoscale(0.75),
        frame("Body", U(1, 0, 1, 0), children=[
            node("Pop", "UIScale", {"Scale": 1}),
            frame("Rays", U(0, 0, 0, 0), U(0.5, 0, 0.5, 0), (0.5, 0.5), ZIndex=1),
            text("Word", "GREAT!", U(1, 40, 0, 88), U(0.5, 0, 0, 8), (0.5, 0), ts=84, color=WHITE, display=True, stroke=6,
                 TextWrapped=False, ZIndex=3, children=[blue()]),
            text("Sub", "x500 COMBO", U(1, 0, 0, 36), U(0.5, 0, 0, 98), (0.5, 0), ts=34, color="#E9FFD9", display=True,
                 stroke=4, TextWrapped=False, ZIndex=3),
        ]),
    ])
    # Lucky Wheel button, top right where the ADMIN button sits (under it for admins). Fixed
    # size like ADMIN; HudController places it (Dev, 2026-10-30: the rail tile went under the
    # wallet on phones).
    spin = button("SpinButton", U(0, 104, 0, 38), U(1, -10, 0, 6), (1, 0), color="#4C8DFF", label="Spin", ts=20, ico="Spin",
                  ico_px=30, stroke=3, Visible=False, children=[badge(px=24)])
    # Tutorial, phones: where to hold a finger to sweep (the right half of the screen,
    # SweepController). TutorialController shows it and pulses the square.
    hold = frame("HoldHint", U(0, 180, 0, 160), U(0.75, 0, 0.5, 0), (0.5, 0.5), Visible=False, ZIndex=17, children=[
        autoscale(),
        frame("Pulse", U(0, 92, 0, 92), U(0.5, 0, 0, 46), (0.5, 0.5), bg=WHITE, BackgroundTransparency=0.55, ZIndex=17,
              children=[border(ACCENT, 4)]),
        text("Label", "HOLD HERE", U(1, 0, 0, 30), U(0.5, 0, 1, -24), (0.5, 1), ts=26, display=True, stroke=3, ZIndex=18),
        text("Sub", "to sweep", U(1, 0, 0, 22), U(0.5, 0, 1, 0), (0.5, 1), ts=19, color=ACCENT, display=True, stroke=2.5, ZIndex=18),
    ])
    # Quests strip (QuestController, Dev 2026-10-31; replaced the 3-goal strip): a slim strip
    # under the World Cleaned bar with the Quest Master's current job. Tap it to open the
    # Quests window. The red "!" badge shows when something can be claimed.
    quests = button("Quests", U(0, 360, 0, 30), U(0.5, 0, 0, 118), (0.5, 0), color=BG, stroke=3, stud=False, Visible=False,
                    children=[
        autoscale(),
        icon("Icon", "TreasureMap", 26, U(0, 4, 0.5, 0), (0, 0.5)),
        text("Count", "JOB 1", U(0, 64, 1, 0), U(0, 32, 0, 0), ts=15, color=PREMIUM, display=True, stroke=2, xa="Left",
             TextWrapped=False),
        # QuestController fits the text to the space (Ui.fitText); the progress has its own label.
        text("Next", "", U(1, -186, 1, -4), U(0, 96, 0, 2), ts=16, display=True, stroke=2, xa="Left", TextWrapped=False),
        text("Progress", "", U(0, 76, 1, -4), U(1, -8, 0, 2), (1, 0), ts=15, color="#C9D0DE", display=True, stroke=2,
             xa="Right", TextWrapped=False),
        frame("Bar", U(1, -6, 0, 3), U(0, 3, 1, -4), bg="#14171D", children=[
            frame("Fill", U(0, 0, 1, 0), bg=ACCENT),
        ]),
        badge(px=22),
    ])
    write("Hud", screen([rail, spin, pills, moon, quests, boosts, boost_tip, toasts, announcement, wallet, right, hotbar, hint, combo, burst, picker,
                         spot, pointer, hold], order=1))


# ---------------------------------------------------------------- Shop
SHOP_TABS_W = 150  # category tabs down the left side
SHOP_CELL = (196, 226)  # 3 tiles per row in the 612 px wide page
SHOP_LUCK_H = 132  # LUCK_H in ShopController
SHOP_BANNER_H = 168  # BANNER_H in ShopController


def fit(mx, mn=MIN_FIT):
    return node("Fit", "UITextSizeConstraint", {"MaxTextSize": mx, "MinTextSize": mn})


def shop():
    """Shop, redesigned for kids (Dev, 2026-10-31: the old one-long-scroll shop was
    "hella clustered"). Tabs down the left switch PAGES (one thing at a time): Deals, Eggs,
    Passes, Boosts, Potions, Cash. A page is a column of big pieces: wide banners (Starter
    Pack, the limited pack) whose contents are pictures, the Server Luck card, and a grid of
    tiles: a big picture, a short name, one short line and one price button. A pink gift
    corner sits on giftable tiles. Egg tiles open a "How many?" picker (x1 / x3 / x10).
    ShopController clones Tab, Banner, Chip, Tile, Grid, LuckCard, Offer and Option."""
    tab = button("Template", U(1, 0, 0, 62), color=HEADER, stroke=3, Visible=False, children=[
        icon("Icon", "Star", 44, U(0, 6, 0.5, 0), (0, 0.5)),
        text("Label", "Tab", U(1, -58, 1, -6), U(0, 54, 0.5, 0), (0, 0.5), ts=21, display=True, stroke=2.5, xa="Left",
             TextScaled=True, children=[fit(21)]),
        frame("Lit", U(0, 8, 1, 0), U(1, 0, 0, 0), (1, 0), bg=WHITE, Visible=False, ZIndex=4),
        badge(z=6, px=26),
    ])
    tab_list = scroller("List", U(1, -6, 1, -12), U(0, 3, 0, 6), [vlist(8), padding(3, 3, 3, 3), tab])
    tab_list["properties"].update(ScrollBarThickness=5, VerticalScrollBarInset="ScrollBar")
    tabs = plate("Tabs", U(0, SHOP_TABS_W, 1, -88), U(0, 12, 0, 76), tint="#E3E7EF", stroke=3, children=[tab_list])

    # Page title: big and friendly, with the page's one-line promise on the right.
    title = frame("PageTitle", U(1, 0, 0, 44), LayoutOrder=0, Visible=False, children=[
        icon("Icon", "Star", 42, U(0, 0, 0.5, 0), (0, 0.5)),
        text("Title", "Deals", U(0.55, -50, 1, 0), U(0, 50, 0, 0), ts=32, color=INK, display=True, xa="Left",
             TextScaled=True, children=[fit(32)]),
        text("Note", "", U(0.45, 0, 1, 0), U(1, 0, 0, 0), (1, 0), ts=18, color=SUB, display=True, xa="Right",
             TextScaled=True, children=[fit(18)]),
        frame("Rule", U(1, 0, 0, 5), U(0, 0, 1, 0), (0, 1), bg=HEADER),
    ])
    # Banner: Starter Pack and the limited pack. What's inside is shown as pictures (Chips).
    chip = frame("Chip", U(0, 66, 0, 84), Visible=False, children=[
        frame("Back", U(0, 60, 0, 60), U(0.5, 0, 0, 0), (0.5, 0), bg=WHITE, BackgroundTransparency=0.82, ZIndex=3, children=[
            node("Stroke", "UIStroke", {"Color": WHITE, "Thickness": 2, "Transparency": 0.4, "ApplyStrokeMode": "Border"}),
        ]),
        icon("Icon", "Egg", 50, U(0.5, 0, 0, 5), (0.5, 0), ZIndex=4),
        node("Model", "ViewportFrame", base(U(0, 56, 0, 56), U(0.5, 0, 0, 2), (0.5, 0), BackgroundTransparency=1, Visible=False,
                                            ZIndex=4)),
        text("Caption", "", U(1, 6, 0, 22), U(0.5, 0, 1, 0), (0.5, 1), ts=16, display=True, stroke=2, ZIndex=4,
             TextScaled=True, children=[fit(16)]),
    ])
    banner = plate("Banner", U(1, 0, 0, SHOP_BANNER_H), tint="#FF4D5E", Visible=False, children=[
        node("Art", "ImageLabel", base(U(1, 0, 1, 0), BackgroundTransparency=1, Image="", ScaleType="Crop", ZIndex=1)),
        node("Glow", "ImageLabel", base(U(0, 300, 0, 300), U(1, -100, 0.5, 0), (0.5, 0.5), BackgroundTransparency=1,
                                        Image=img("Glow"), ImageColor3=WHITE, ImageTransparency=0.55, ZIndex=1)),
        plate("Tag", U(0, 170, 0, 30), U(0, 12, 0, 10), tint=BADGE_RED, stroke=3, ZIndex=3, children=[
            text("Label", "SPECIAL OFFER", U(1, -8, 1, 0), U(0, 4, 0, 0), ts=17, display=True, stroke=2, ZIndex=4,
                 TextScaled=True, children=[fit(17)]),
        ]),
        text("Title", "Starter Pack", U(1, -400, 0, 34), U(0, 192, 0, 8), ts=30, display=True, stroke=3, xa="Left", ZIndex=3,
             TextScaled=True, children=[fit(30)]),
        frame("Items", U(1, -200, 0, 88), U(0, 12, 0, 54), ZIndex=3, children=[hlist(4, h="Left", v="Top")]),
        text("Timer", "", U(0, 200, 0, 26), U(1, -12, 0, 12), (1, 0), ts=19, display=True, stroke=2.5, color=PREMIUM, ZIndex=3),
        # Worth: what the same things cost in the shop, struck through above the price.
        text("Worth", "", U(0, 160, 0, 26), U(1, -12, 1, -76), (1, 1), ts=20, display=True, stroke=2.5, ZIndex=3,
             children=[frame("Strike", U(0, 74, 0, 3), U(0.5, 0, 0.5, 0), (0.5, 0.5), bg=DANGER, ZIndex=4)]),
        button("Buy", U(0, 160, 0, 58), U(1, -12, 1, -12), (1, 1), color=PREMIUM, label="", ts=28, label_color=INK, ZIndex=3),
    ])
    # A limited offer the game made you (backpack full, rare egg growing...): stays a while.
    offer = plate("Offer", U(1, 0, 0, 104), tint="#FF5FA2", Visible=False, children=[
        node("Glow", "ImageLabel", base(U(0, 140, 0, 140), U(0, 50, 0.5, 0), (0.5, 0.5), BackgroundTransparency=1, Image=img("Glow"),
                                        ImageColor3=WHITE, ImageTransparency=0.35, ZIndex=1)),
        icon("Icon", "Star", 78, U(0, 50, 0.5, 0), (0.5, 0.5)),
        plate("Tag", U(0, 140, 0, 26), U(0, 98, 0, 10), tint=BADGE_RED, stroke=3, ZIndex=3, children=[
            text("Label", "LIMITED OFFER", U(1, 0, 1, 0), ts=16, display=True, stroke=2, ZIndex=4),
        ]),
        text("Timer", "", U(0, 120, 0, 26), U(0, 246, 0, 10), ts=17, display=True, stroke=2.5, xa="Left", color=PREMIUM, ZIndex=3),
        text("Title", "", U(1, -290, 0, 30), U(0, 98, 0, 38), ts=24, display=True, stroke=3, xa="Left", ZIndex=3,
             TextScaled=True, children=[fit(24)]),
        text("Desc", "", U(1, -290, 0, 30), U(0, 98, 0, 68), ts=16, heavy=True, stroke=2, xa="Left", ya="Top", ZIndex=3,
             TextScaled=True, children=[fit(16)]),
        button("Buy", U(0, 170, 0, 54), U(1, -12, 0.5, 0), (1, 0.5), color=PREMIUM, label="", ts=26, label_color=INK, ZIndex=3),
    ])
    # Server Luck (Dev, 2026-10-31, from a reference): level now > next level, a shared
    # "Ends in" timer and the price of the next level.
    luck = plate("LuckCard", U(1, 0, 0, SHOP_LUCK_H), tint="#5CC930", Visible=False, children=[
        node("Glow", "ImageLabel", base(U(0, 150, 0, 150), U(0, 62, 0.5, 0), (0.5, 0.5), BackgroundTransparency=1, Image=img("Glow"),
                                        ImageColor3=WHITE, ImageTransparency=0.35, ZIndex=1)),
        icon("Icon", "LuckyClover", 100, U(0, 62, 0.5, 0), (0.5, 0.5)),
        text("Title", "Server Luck", U(0, 260, 0, 28), U(0, 124, 0, 10), ts=24, display=True, stroke=3, xa="Left",
             color="#E4FF8A", ZIndex=3),
        text("Levels", "1x > 2x", U(1, -320, 0, 56), U(0, 124, 0, 38), ts=50, display=True, stroke=3.5, xa="Left",
             ZIndex=3, RichText=True, TextScaled=True, children=[fit(50, 14)]),
        text("Desc", "", U(1, -320, 0, 22), U(0, 124, 0, 96), ts=16, heavy=True, stroke=2, xa="Left", ZIndex=3,
             TextScaled=True, children=[fit(16)]),
        text("Timer", "", U(0, 180, 0, 26), U(1, -12, 0, 12), (1, 0), ts=19, display=True, stroke=2.5, color="#FF5A3C", ZIndex=3),
        button("Buy", U(0, 180, 0, 58), U(1, -12, 1, -14), (1, 1), color=PREMIUM, label="", ts=28, label_color=INK, ZIndex=3),
    ])
    cw, ch = SHOP_CELL
    grid = frame("Grid", U(1, 0, 0, 0), Visible=False, AutomaticSize="Y", children=[
        node("Layout", "UIGridLayout", {"CellSize": U(0, cw, 0, ch), "CellPadding": U(0, 12, 0, 12), "SortOrder": "LayoutOrder",
                                        "HorizontalAlignment": "Left"}),
    ])
    # Tile: big picture on a light burst, the name, one short line, one price button.
    tile = plate("Tile", U(0, cw, 0, ch), tint=HEADER, stroke=3, Visible=False, children=[
        node("Glow", "ImageLabel", base(U(0, 190, 0, 190), U(0.5, 0, 0, 62), (0.5, 0.5), BackgroundTransparency=1, Image=img("Glow"),
                                        ImageColor3=WHITE, ImageTransparency=0.2, ZIndex=1)),
        icon("Icon", "Shop", 96, U(0.5, 0, 0, 8), (0.5, 0)),
        node("Model", "ViewportFrame", base(U(0, 104, 0, 104), U(0.5, 0, 0, 4), (0.5, 0), BackgroundTransparency=1, Visible=False,
                                            ZIndex=3)),
        plate("Tag", U(0, 112, 0, 26), U(0, -6, 0, 6), tint=BADGE_RED, stroke=2.5, Visible=False, ZIndex=5, children=[
            text("Label", "BEST", U(1, -6, 1, 0), U(0, 3, 0, 0), ts=16, display=True, stroke=2, ZIndex=6,
                 TextScaled=True, children=[fit(16)]),
        ]),
        button("Gift", U(0, 40, 0, 40), U(1, -6, 0, 6), (1, 0), color="#FF7EB6", ico="Gift", ico_px=30, stroke=3,
               Visible=False, ZIndex=5),
        text("Name", "Item", U(1, -12, 0, 30), U(0.5, 0, 0, 106), (0.5, 0), ts=24, display=True, stroke=2.5, ZIndex=3,
             TextScaled=True, children=[fit(24)]),
        text("Sub", "", U(1, -14, 0, 24), U(0.5, 0, 0, 136), (0.5, 0), ts=18, color="#FFF6C8", display=True, stroke=2, ZIndex=3,
             TextScaled=True, children=[fit(18)]),
        button("Buy", U(1, -16, 0, 50), U(0.5, 0, 1, -8), (0.5, 1), color=PREMIUM, label="", ts=26, label_color=INK, ZIndex=3),
    ])
    lst = scroller("List", U(1, -(SHOP_TABS_W + 30), 1, -84), U(0, SHOP_TABS_W + 22, 0, 74),
                   [vlist(14), padding(4, 14, 4, 12)])
    empty = text("Empty", "Nothing here right now. Check back soon!", U(1, -(SHOP_TABS_W + 60), 0, 60),
                 U(0, SHOP_TABS_W + 40, 0.5, 0), (0, 0.5), ts=20, color=SUB, heavy=True, Visible=False)
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
    # "How many?" picker for eggs: three big choices, the middle one marked MOST POPULAR.
    option = plate("Option", U(0, 170, 0, 238), tint="#FF5FA2", stroke=3, Visible=False, ZIndex=12, children=[
        node("Glow", "ImageLabel", base(U(0, 170, 0, 170), U(0.5, 0, 0, 66), (0.5, 0.5), BackgroundTransparency=1, Image=img("Glow"),
                                        ImageColor3=WHITE, ImageTransparency=0.25, ZIndex=12)),
        node("Model", "ViewportFrame", base(U(0, 104, 0, 104), U(0.5, 0, 0, 14), (0.5, 0), BackgroundTransparency=1, ZIndex=13)),
        plate("Tag", U(0, 150, 0, 26), U(0.5, 0, 0, -13), (0.5, 0), tint=BADGE_RED, stroke=2.5, Visible=False, ZIndex=15, children=[
            text("Label", "MOST POPULAR", U(1, -6, 1, 0), U(0, 3, 0, 0), ts=16, display=True, stroke=2, ZIndex=16,
                 TextScaled=True, children=[fit(16)]),
        ]),
        text("Count", "x1", U(1, 0, 0, 44), U(0.5, 0, 0, 112), (0.5, 0), ts=40, display=True, stroke=3, ZIndex=14),
        text("Each", "", U(1, -10, 0, 22), U(0.5, 0, 0, 154), (0.5, 0), ts=16, color="#FFF6C8", display=True, stroke=2, ZIndex=14,
             TextScaled=True, children=[fit(16)]),
        button("Buy", U(1, -16, 0, 50), U(0.5, 0, 1, -8), (0.5, 1), color=PREMIUM, label="", ts=26, label_color=INK, ZIndex=14),
    ])
    qty = plate("QtyPicker", U(0, 600, 0, 380), U(0.5, 0, 0.5, 20), (0.5, 0.5), SURFACE, Visible=False, ZIndex=11, children=[
        plate("Header", U(1, 0, 0, 56), tint="#FF5FA2", ZIndex=11, children=[
            icon("Icon", "Egg", 42, U(0, 8, 0.5, 0), (0, 0.5), ZIndex=12),
            text("Title", "How many?", U(1, -120, 1, 0), U(0, 58, 0, 0), ts=30, display=True, stroke=3, xa="Left", ZIndex=12),
        ]),
        button("Close", U(0, 48, 0, 48), U(1, -6, 0, 6), (0.5, 0.5), color=DANGER, label="X", ts=28, ZIndex=13),
        text("Note", "Bought eggs always hatch their own rarity!", U(1, -24, 0, 24), U(0.5, 0, 0, 64), (0.5, 0), ts=18,
             color=SUB, display=True, ZIndex=12),
        frame("Options", U(1, -24, 0, 250), U(0.5, 0, 1, -16), (0.5, 1), ZIndex=12, children=[
            hlist(16, h="Center", v="Bottom"), option,
        ]),
    ])
    write("Shop", screen([dim(), window(WIN_W, WIN_H, "Shop", "Shop",
                                        [tabs, lst, title, banner, chip, offer, luck, grid, tile, empty, gift, qty],
                                        header="#E9A21F")],
                         order=10, enabled=False))


# ---------------------------------------------------------------- Index
def bar(name, size, pos, anchor, fill, label, ts=26):
    return frame(name, size, pos, anchor, bg="#0B0E1E", children=[
        border(INK, 3),
        frame("Fill", U(0.3, 0, 1, 0), bg=fill, children=[]),
        text("Label", label, U(1, 0, 1, 0), ts=ts, display=True, stroke=3, ZIndex=4),
    ])


INDEX_TABS = [("Common", "#BEBEBE"), ("Uncommon", "#4FD36B"), ("Rare", "#3E9BFF"), ("Epic", "#B05CFF"),
              ("Legendary", "#FFB020"), ("Mythic", "#FF3B5C"), ("Cosmic", "#FF78E6"), ("Daily", "#5B6070")]


def index():
    """Pet index (Dev, 2026-10-31, from a reference): one rarity at a time (tabs down the
    right), cards with "1 in N" (the chance within its egg) and the zone, "???" silhouettes
    for pets you haven't hatched, a "complete the set" reward strip and a found bar."""
    card = button("Template", U(0, 0, 0, 0), color="#BEBEBE", stroke=3, Visible=False, children=[
        node("Viewport", "ViewportFrame", base(U(1, -10, 1, -50), U(0.5, 0, 0, 24), (0.5, 0), BackgroundTransparency=1,
                                               Ambient="#C8D0E8", LightColor=WHITE, LightDirection=[-1, -1, -1], ZIndex=2)),
        text("Chance", "1 in 5", U(0.6, 0, 0, 20), U(0, 6, 0, 4), ts=16, display=True, stroke=2, xa="Left", ZIndex=4),
        text("Zone", "", U(0.5, 0, 0, 18), U(1, -6, 0, 5), (1, 0), ts=13, color="#E0E4F0", display=True, stroke=2, xa="Right",
             ZIndex=4, TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 14, "MinTextSize": 7})]),
        text("Name", "???", U(1, -8, 0, 24), U(0.5, 0, 1, -4), (0.5, 1), ts=19, display=True, stroke=2.5, ZIndex=4,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 20, "MinTextSize": 9})]),
    ])
    grid_w = 600
    body = plate("Body", U(0, grid_w, 0, 304), U(0, 12, 0, 76), tint=BG, stud=0.6, children=[
        scroller("Grid", U(1, -12, 1, -12), U(0, 6, 0, 6), [
            node("Layout", "UIGridLayout", {"CellSize": U(0, 136, 0, 150), "CellPadding": U(0, 8, 0, 8), "SortOrder": "LayoutOrder",
                                            "HorizontalAlignment": "Left"}),
            padding(4), card,
        ]),
    ])
    sets = plate("Set", U(0, grid_w, 0, 66), U(0, 12, 0, 388), tint="#3A404D", stroke=3, children=[
        icon("Icon", "PotionCash", 54, U(0, 8, 0.5, 0), (0, 0.5)),
        text("Title", "COMPLETE THE COMMON SET", U(1, -270, 0, 28), U(0, 70, 0, 6), ts=20, display=True, stroke=2.5, xa="Left",
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 20, "MinTextSize": 9})]),
        text("Reward", "2x Cash Potion", U(1, -270, 0, 24), U(0, 70, 0, 34), ts=18, color=PREMIUM, display=True, stroke=2,
             xa="Left", TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 18, "MinTextSize": 9})]),
        button("Claim", U(0, 186, 0, 50), U(1, -8, 0.5, 0), (1, 0.5), color=MUTED, label="0/0 FOUND", ts=20),
    ])
    found = bar("Found", U(0, grid_w, 0, 50), U(0, 12, 1, -12), (0, 1), "#4CC3FF", "0/0 Found", ts=26)
    tabs = frame("Tabs", U(0, 184, 0, 410), U(1, -12, 0, 76), (1, 0), children=[
        vlist(5),
    ] + [button(name, U(1, 0, 0, 46), color=color, label=name if name != "Daily" else "Exclusive", ts=22, LayoutOrder=i)
         for i, (name, color) in enumerate(INDEX_TABS)])
    total = text("Total", "Unlocked: 0/0", U(0, 184, 0, 20), U(1, -12, 1, -10), (1, 1), ts=16, color=SUB, display=True)
    write("Index", screen([dim(), window(WIN_W, WIN_H, "Pet Index", "Index", [body, sets, found, tabs, total], header="#4CC3FF")],
                         order=10, enabled=False))


# ---------------------------------------------------------------- Inventory
SEE = "#0B0E1E"  # see-through dark (native backpack look)


def inventory():
    """Bag: a copy of Roblox's backpack inventory. A see-through dark panel above the
    hotbar with a search box and a grid of tiles in the hotbar's own style (the 3D pet or
    egg, its name, a count for stacks, a pet's passive). Tap a tile to use it (hold a pet or
    an egg, use a potion after a confirm). Drag tiles onto hotbar slots, and hotbar slots
    back onto the panel. Things in the hotbar aren't listed here."""
    W, H = 760, 330
    tile = button("Template", U(0, 0, 0, 0), color=SEE, stroke=3, BackgroundTransparency=0.35, Visible=False, children=[
        node("Viewport", "ViewportFrame", base(U(1, -8, 1, -26), U(0.5, 0, 0, 4), (0.5, 0), BackgroundTransparency=1,
                                               Ambient="#C8D0E8", LightColor=WHITE, LightDirection=[-1, -1, -1], ZIndex=2)),
        icon("Icon", "Potion", 60, U(0.5, 0, 0, 8), (0.5, 0), Visible=False),
        text("Name", "", U(1, -6, 0, 20), U(0.5, 0, 1, -3), (0.5, 1), ts=16, display=True, stroke=2, ZIndex=4, TextWrapped=False,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 16, "MinTextSize": 7})]),
        text("Passive", "", U(1, -6, 0, 14), U(0.5, 0, 1, -22), (0.5, 1), ts=13, color="#7CF58A", display=True, stroke=1.5,
             Visible=False, ZIndex=4, TextWrapped=False,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 13, "MinTextSize": 6})]),
        text("Count", "", U(0, 44, 0, 20), U(1, -4, 0, 2), (1, 0), ts=16, display=True, stroke=2, xa="Right", Visible=False, ZIndex=4),
        # New since you last opened the bag (Dev: hard to tell what's new).
        frame("New", U(0, 46, 0, 20), U(0, 3, 0, 3), bg=BADGE_RED, Visible=False, ZIndex=5, children=[
            border(WHITE, 2),
            text("Label", "NEW", U(1, -4, 1, 0), U(0, 2, 0, 0), ts=16, display=True, stroke=2, ZIndex=6,
                 TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 16, "MinTextSize": 8})]),
        ]),
    ])
    grid = scroller("Grid", U(1, -20, 1, -64), U(0, 10, 0, 56), [
        node("Layout", "UIGridLayout", {"CellSize": U(0, 96, 0, 96), "CellPadding": U(0, 8, 0, 8), "SortOrder": "LayoutOrder",
                                        "HorizontalAlignment": "Left"}),
        padding(4, 12, 4, 4), tile,
    ])
    search = node("Search", "TextBox", base(U(0, 240, 0, 36), U(1, -58, 0, 10), (1, 0), BackgroundColor3="#000000",
                                            BackgroundTransparency=0.4, Text="", PlaceholderText="Search", PlaceholderColor3="#9AA3B8",
                                            TextColor3=WHITE, TextSize=18, FontFace=BODY_HEAVY, ClearTextOnFocus=False,
                                            TextXAlignment="Left", ZIndex=3), [padding(10, 10, 0), border("#5B6070", 2)])
    close = button("Close", U(0, 38, 0, 38), U(1, -10, 0, 9), (1, 0), color=DANGER, label="X", ts=22, stroke=3)
    win = frame("Window", U(0, W, 0, H), U(0.5, 0, 1, -112), (0.5, 1), bg="#0B0E1E", BackgroundTransparency=0.3, children=[
        autoscale(),
        text("Title", "Inventory", U(0, 160, 0, 36), U(0, 12, 0, 10), ts=24, display=True, stroke=2.5, xa="Left"),
        # Filters (Dev, 2026-10-30, in place of the totals line): All / Pets / Eggs / Items,
        # each with its count. While the pointer is on a tile (PC) the Info line shows that
        # tile instead: name, rarity, weight, passive.
        frame("Tabs", U(0, 304, 0, 34), U(0, 150, 0, 11), children=[
            hlist(6, "Left", "Center"),
            button("All", U(0, 52, 0, 32), color="#4C8DFF", label="All", ts=16, stroke=2, LayoutOrder=1),
            button("Pets", U(0, 74, 0, 32), color="#4C8DFF", label="Pets", ts=16, stroke=2, LayoutOrder=2),
            button("Eggs", U(0, 74, 0, 32), color="#4C8DFF", label="Eggs", ts=16, stroke=2, LayoutOrder=3),
            button("Items", U(0, 82, 0, 32), color="#4C8DFF", label="Items", ts=16, stroke=2, LayoutOrder=4),
        ]),
        text("Info", "", U(0, 304, 0, 36), U(0, 150, 0, 10), ts=16, color="#C8D0E8", display=True, stroke=1.5, xa="Left",
             Visible=False, TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 16, "MinTextSize": 7})]),
        search, close, grid,
        text("Empty", "", U(1, -40, 0, 60), U(0.5, 0, 0.55, 0), (0.5, 0.5), ts=19, color="#C8D0E8", heavy=True, Visible=False),
    ])
    write("Inventory", screen([win], order=6, enabled=False))


# ---------------------------------------------------------------- Base panels (Active pets / Growing eggs)
SAND = "#E9D3B0"


def side_button(name, label, ico, color, order):
    return button(name, U(0, 80, 0, 80), color=color, LayoutOrder=order, children=[
        icon("Icon", ico, 56, U(0.5, 0, 0, 4), (0.5, 0)),
        text("Label", label, U(1, -4, 0, 20), U(0.5, 0, 1, -4), (0.5, 1), ts=17, display=True, stroke=2.5,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 17, "MinTextSize": 7})]),
        badge(),
    ])


POPUP_W, POPUP_H = 440, 460  # Pets / Growing Eggs side popups


def popup_list(screen_name, title, ico, header_color, head_button, row_children, footer, row_h=74):
    """Pets / Eggs: a small popup beside the Eggs / Pets buttons (BasePanelsController places
    it) with a one-column list. No dim: the game stays visible; a click outside closes it."""
    row = plate("Template", U(0, 0, 0, 0), tint="#2E3340", stroke=3, Visible=False, children=[
        node("Viewport", "ViewportFrame", base(U(0, 62, 0, 62), U(0, 4, 0.5, 0), (0, 0.5), BackgroundTransparency=1,
                                               Ambient="#C8D0E8", LightColor=WHITE, LightDirection=[-1, -1, -1], ZIndex=2)),
        text("Name", "", U(1, -190, 0, 26), U(0, 72, 0, 8), ts=20, display=True, stroke=2.5, xa="Left",
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 20, "MinTextSize": 10})]),
        text("Sub", "", U(1, -190, 0, 22), U(0, 72, 0, 36), ts=17, color="#7CFF8C", display=True, stroke=2, xa="Left"),
        # The whole row is a button (the Pets panel opens the pet's info). It must stay under
        # Action (lower ZIndex): at the same ZIndex it can take Action's clicks.
        node("Select", "TextButton", base(U(1, 0, 1, 0), BackgroundTransparency=1, Text="", ZIndex=0)),
    ] + row_children)
    list_bottom = 8 if not footer else 72 if len(footer) == 1 else 128
    title_room = 258 if head_button else 110  # the title stops before Open All / Close
    win = plate("Window", U(0, POPUP_W, 0, POPUP_H), U(1, -110, 0.5, -30), (1, 0.5), SURFACE, children=[
        autoscale(),
        plate("Header", U(1, 0, 0, 56), tint=header_color, children=[
            icon("Icon", ico, 42, U(0, 8, 0.5, 0), (0, 0.5)),
            text("Title", title, U(1, -title_room, 1, -8), U(0, 58, 0.5, 0), (0, 0.5), ts=26, display=True, stroke=3, xa="Left",
                 TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 26, "MinTextSize": 12})]),
        ]),
        button("Close", U(0, 42, 0, 42), U(1, -4, 0, 4), (0.5, 0.5), color=DANGER, label="X", ts=24, ZIndex=6),
        head_button,
        scroller("List", U(1, -16, 1, -(64 + list_bottom)), U(0, 8, 0, 64), [
            node("Layout", "UIGridLayout", {"CellSize": U(1, -14, 0, row_h), "CellPadding": U(0, 8, 0, 8), "SortOrder": "LayoutOrder",
                                            "HorizontalAlignment": "Left"}),
            padding(2, 12, 2, 2), row,
        ]),
        text("Empty", "", U(1, -50, 0, 80), U(0.5, 0, 0.45, 0), (0.5, 0.5), ts=20, color=SUB, heavy=True, Visible=False),
    ] + (footer or []))
    away = node("ClickAway", "TextButton", base(U(1, 400, 1, 400), U(0.5, 0, 0.5, 0), (0.5, 0.5), BackgroundTransparency=1,
                                                Text="", AutoButtonColor=False, ZIndex=0))
    write(screen_name, screen([away, win], order=10, enabled=False))


def base_panels():
    # Eggs / Pets / Gear / Quests buttons on the right edge (BasePanelsController lays them
    # out: stacked on PC, a column from the top right on phones).
    buttons = frame("Buttons", U(0, 80, 0, 432), U(1, -14, 0.5, -130), (1, 1), children=[
        autoscale(compact=0.88),
        side_button("EggsButton", "Eggs", "Egg", DANGER, 1),
        side_button("PetsButton", "Pets", "Alien", "#FF9A3C", 2),
        side_button("ToolsButton", "Gear", "Tools", "#4C8DFF", 3),
        side_button("QuestsButton", "Quests", "Quest", "#9B6BFF", 4),
    ])
    write("BasePanels", screen([buttons], order=4))
    head = dict(size=U(0, 132, 0, 40), pos=U(1, -50, 0, 28), anchor=(1, 0.5))
    popup_list(
        "PetsPanel", "0/4 Active", "Alien", "#FF9A3C", None,
        [button("Action", U(0, 104, 0, 44), U(1, -8, 0.5, 0), (1, 0.5), color=DANGER, label="Unequip", ts=18, ZIndex=3),
         # Fight stats under the cash line (2026-10-31): sword + damage per hit, bolt + seconds per hit.
         frame("Stats", U(1, -190, 0, 22), U(0, 72, 0, 62), children=[
             hlist(5, "Left"),
             icon("DamageIcon", "Sword", 22, LayoutOrder=1),
             text("Damage", "", U(0, 0, 1, 0), ts=17, color="#FF9A7A", display=True, stroke=2, xa="Left",
                  TextWrapped=False, AutomaticSize="X", LayoutOrder=2),
             frame("Gap", U(0, 6, 1, 0), LayoutOrder=3),
             icon("RateIcon", "Boost", 22, LayoutOrder=4),
             text("Rate", "", U(0, 0, 1, 0), ts=17, color="#8FD3FF", display=True, stroke=2, xa="Left",
                  TextWrapped=False, AutomaticSize="X", LayoutOrder=5),
         ])],
        [
            # Two ways to more slots: one for cash, three for Robux (the pass).
            button("BuySlot", U(0.5, -14, 0, 46), U(0, 10, 1, -66), (0, 1), color=SUCCESS, label="+1 Slot", ts=18),
            button("AddSlot", U(0.5, -14, 0, 46), U(1, -10, 1, -66), (1, 1), color=PREMIUM, label="+3 Slots", ts=18,
                   label_color=INK),
            button("EquipBest", U(1, -20, 0, 46), U(0.5, 0, 1, -10), (0.5, 1), color="#4C8DFF", label="Equip Best", ts=22),
        ], row_h=92)
    popup_list(
        "EggsPanel", "Growing Eggs", "Egg", DANGER,
        button("OpenAll", head["size"], head["pos"], head["anchor"], color=PREMIUM, label="Open All", ts=18, label_color=INK, ZIndex=5),
        [button("Action", U(0, 104, 0, 44), U(1, -8, 0.5, 0), (1, 0.5), color=SUCCESS, label="Open", ts=18, ZIndex=3)],
        None)


# ---------------------------------------------------------------- Hover card (pets and eggs in parks)
def hover():
    # Minimal: outlined text next to the cursor, no panel (it can pop up at any time).
    line = lambda name, order, ts, color, stroke=2.5: text(name, "", U(1, 0, 0, ts + 4), ts=ts, color=color, display=True,
                                                           stroke=stroke, xa="Left", LayoutOrder=order, TextWrapped=False)
    card = frame("Card", U(0, 260, 0, 0), AutomaticSize="Y", Visible=False, ZIndex=10, children=[
        autoscale(), vlist(0, "Left", "Top"),
        line("Name", 1, 24, WHITE, 3),
        line("Income", 2, 20, "#7CFF8C"),
        line("Weight", 3, 16, WHITE, 2),
        line("Extra", 4, 15, "#C8D0E8", 2),
    ])
    tree = screen([card], order=30, inset=True)
    tree["properties"]["ScreenInsets"] = "None"
    write("Hover", tree)


# ---------------------------------------------------------------- Egg placement banner
def placing():
    """Shown while holding an egg (what you're placing, Cancel, Go to Base when far) or a pet
    (Place in park, Put away)."""
    bar_ = plate("Bar", U(0, 520, 0, 92), U(0.5, 0, 1, -112), (0.5, 1), BG, stud=0.5, children=[
        autoscale(),
        icon("Icon", "Egg", 76, U(0, 6, 0.5, 0), (0, 0.5)),
        node("Model", "ViewportFrame", base(U(0, 80, 0, 80), U(0, 4, 0.5, 0), (0, 0.5), BackgroundTransparency=1,
                                            Ambient="#C8D0E8", LightColor=WHITE, LightDirection=[-1, -1, -1], ZIndex=2, Visible=False)),
        text("Title", "Click a spot in your pet park", U(1, -250, 0, 32), U(0, 88, 0, 12), ts=22, color=WHITE, display=True,
             stroke=2.5, xa="Left", TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 22, "MinTextSize": 10})]),
        text("Sub", "", U(1, -250, 0, 26), U(0, 88, 0, 50), ts=17, color=ACCENT, heavy=True, xa="Left", stroke=2,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 17, "MinTextSize": 7})]),
        button("GoBase", U(0, 140, 0, 44), U(1, -10, 0, 8), (1, 0), color=SUCCESS, label="Go to Base", ts=18, Visible=False),
        button("PlacePet", U(0, 140, 0, 44), U(1, -10, 0, 8), (1, 0), color=SUCCESS, label="Place in park", ts=17, Visible=False),
        # Egg in hand at your park: puts it on a free spot for you (Dev: new players found
        # aiming at a spot hard).
        button("AutoPlace", U(0, 140, 0, 44), U(1, -10, 0, 8), (1, 0), color=SUCCESS, label="Place for me", ts=17, Visible=False),
        button("Cancel", U(0, 140, 0, 34), U(1, -10, 1, -8), (1, 1), color=DANGER, label="Cancel (Q)", ts=16),
    ])
    write("Placing", screen([bar_], order=8, enabled=False))


# ---------------------------------------------------------------- Rewards (daily, playtime, group, event)
def reward_card(name, top, order, w, h, ico_px, wrap=False):
    """Daily / gift card: label on top, big icon, reward text, a CLAIMED overlay.
    wrap: the reward text may take two lines ("Rare Egg + Huge Charm")."""
    label_h = 30 if wrap else 22
    return button(name, U(0, w, 0, h), color=WHITE, stroke=3, LayoutOrder=order, children=[
        text("Day", top, U(1, 0, 0, 24), U(0.5, 0, 0, 2), (0.5, 0), ts=18, color=INK, display=True, ZIndex=4),
        icon("Icon", "Gift", ico_px, U(0.5, 0, 0.5, -2 if wrap else 2), (0.5, 0.5)),
        text("Reward", "", U(1, -6, 0, label_h), U(0.5, 0, 1, -3), (0.5, 1), ts=15, color=INK, display=True, ZIndex=4,
             TextScaled=True,
             children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 16 if not wrap else 14, "MinTextSize": 8})]),
        frame("Done", U(1, 0, 1, 0), bg="#0B0E1E", BackgroundTransparency=0.45, Visible=False, ZIndex=6, children=[
            text("Label", "✓", U(1, 0, 1, 0), ts=54, color=SUCCESS, display=True, stroke=3, ZIndex=7),
        ]),
    ])


DAY_COLORS = {1: "#3FB4FF", 2: "#3FB4FF", 3: "#3FB4FF", 4: "#A35CFF", 5: "#A35CFF", 6: "#FFB020", 7: "#FF5FA2"}


def daily_card(i, w, h, big=False):
    """Daily card like Dev's reference (2026-10-31): a bright colour block with rays behind the
    prize, "DAY 3" big on top, the prize, its name, and a status button at the bottom
    (CLAIMED / CLAIM! / a countdown / LOCKED; RewardsController sets it). Day 7 is tall, with
    a rainbow and "THE BEST!" under the title."""
    color = DAY_COLORS[i]
    ico = 128 if big else 66
    kids = [
        border(INK, 3),
        studs(WHITE if big else color, 0.55),
        node("Rays", "ImageLabel", base(U(0, ico * 2, 0, ico * 2), U(0.5, 0, 0.5, -8 if big else -4), (0.5, 0.5),
                                        BackgroundTransparency=1, Image=img("Rays"), ImageColor3=WHITE,
                                        ImageTransparency=0.6, ZIndex=1)),
        text("Day", f"DAY {i}", U(1, -8, 0, 44 if big else 30), U(0.5, 0, 0, 4), (0.5, 0), ts=40 if big else 26,
             color=PREMIUM if big else WHITE, display=True, stroke=3, ZIndex=4),
        icon("Icon", "Gift", ico, U(0.5, 0, 0.5, -8 if big else -4), (0.5, 0.5)),
        text("Reward", "", U(1, -10, 0, 34 if big else 22), U(0.5, 0, 1, -44), (0.5, 1), ts=19 if big else 16, display=True,
             stroke=2.5, ZIndex=4, TextScaled=True,
             children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 19 if big else 16, "MinTextSize": 8})]),
        button("Status", U(1, -16, 0, 34), U(0.5, 0, 1, -6), (0.5, 1), color=DANGER, label="LOCKED", ts=20, stroke=3,
               ZIndex=5),
        frame("Done", U(1, 0, 1, 0), bg="#0B0E1E", BackgroundTransparency=0.55, Visible=False, ZIndex=4),
    ]
    if big:
        kids.append(text("Best", "THE BEST!", U(1, -8, 0, 26), U(0.5, 0, 0, 48), (0.5, 0), ts=22, color=WHITE, display=True,
                         stroke=3, Rotation=-4, ZIndex=4))
        kids.append(node("Rainbow", "UIGradient", {"Color": {"keypoints": [
            [0, "#FF7EB6"], [0.25, "#FFD43B"], [0.5, "#7CF5C8"], [0.75, "#7FD3FF"], [1, "#C59BFF"]]}, "Rotation": 35}))
    p = base(U(0, w, 0, h), BackgroundColor3=WHITE if big else color, Text="", AutoButtonColor=False, ZIndex=1)
    return node(f"Day{i}", "TextButton", p, kids)


def rewards():
    # Daily window (restyled 2026-10-31 from Dev's reference): days 1-6 in two rows of three,
    # a tall day 7 on the right, the claim button and streak up in the header, the event
    # strip along the bottom.
    cw, ch, gap, x0, y0 = 182, 152, 10, 12, 76
    cards = []
    for i in range(1, 7):
        col, row = (i - 1) % 3, (i - 1) // 3
        c = daily_card(i, cw, ch)
        c["properties"]["Position"] = U(0, col * (cw + gap), 0, row * (ch + gap))
        cards.append(c)
    seven = daily_card(7, 796 - 3 * (cw + gap), 2 * ch + gap, big=True)
    seven["properties"]["Position"] = U(0, 3 * (cw + gap), 0, 0)
    cards.append(seven)
    days = frame("Days", U(0, 796, 0, 2 * ch + gap), U(0, x0, 0, y0), children=cards)
    group = plate("Group", U(0.5, -18, 0, 100), U(0, 12, 0, 358), tint="#4C8DFF", stud=0.3, stroke=3, Visible=False, children=[
        icon("Icon", "Group", 70, U(0, 4, 0.5, 0), (0, 0.5)),
        text("Text", "Join our group for 2 Luck Potions + cash!", U(1, -220, 1, -8), U(0, 78, 0, 4), ts=16, display=True,
             stroke=2, xa="Left"),
        button("Claim", U(0, 124, 0, 50), U(1, -10, 0.5, 0), (1, 0.5), color=SUCCESS, label="Claim", ts=22),
    ])
    event = plate("Event", U(1, -24, 0, 98), U(0, 12, 0, 410), tint="#FF78E6", stud=0.3, stroke=3, children=[
        icon("Icon", "Event", 70, U(0, 4, 0.5, 0), (0, 0.5)),
        text("Name", "Egg Rain Weekend", U(1, -220, 0, 28), U(0, 78, 0, 6), ts=21, display=True, stroke=2.5, xa="Left",
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 22, "MinTextSize": 10})]),
        text("Info", "", U(1, -220, 0, 44), U(0, 78, 0, 34), ts=14, display=True, stroke=2, xa="Left", ya="Top",
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 15, "MinTextSize": 8})]),
        button("SignUp", U(0, 124, 0, 50), U(1, -10, 0.5, 0), (1, 0.5), color=PREMIUM, label="Sign up", ts=20, label_color=INK),
    ])
    body = [
        text("Streak", "STREAK 0", U(0, 150, 0, 30), U(1, -282, 0, 32), (1, 0.5), ts=20, color=WHITE, display=True, stroke=2.5,
             xa="Right", ZIndex=5),
        button("ClaimDaily", U(0, 200, 0, 48), U(1, -40, 0, 32), (1, 0.5), color=PREMIUM, label="CLAIM!", ts=24, label_color=WHITE,
               ZIndex=5),
        days,
        group, event,
    ]
    write("Daily", screen([dim(), window(WIN_W, WIN_H, "Daily Rewards", "Daily", body, header="#3FB4FF")], order=10, enabled=False))

    # Playtime gifts: their own window (green Gifts button on the rail), fitted to its six
    # cards (Dev, 2026-10-31: it was too big).
    gw, gh = 592, 446
    gifts = frame("Gifts", U(0, 3 * 178 + 2 * 12, 0, 2 * 148 + 12), U(0.5, 0, 0, 118), (0.5, 0), children=[
        node("Layout", "UIGridLayout", {"CellSize": U(0, 178, 0, 148), "CellPadding": U(0, 12, 0, 12), "SortOrder": "LayoutOrder",
                                        "HorizontalAlignment": "Center"}),
    ] + [reward_card(f"Gift{i}", "5:00", i, 178, 148, 84) for i in range(1, 7)])
    gift_body = [
        text("Info", "Free gifts the longer you play! They reset when you rejoin.", U(1, -24, 0, 26), U(0.5, 0, 0, 78), (0.5, 0),
             ts=18, color=SUB, heavy=True),
        gifts,
    ]
    write("Playtime", screen([dim(), window(gw, gh, "Playtime Gifts", "Gift", gift_body, header=SUCCESS, size=(gw, gh))],
                             order=10, enabled=False))

    # Leave screen (Dev, 2026-10-31, from a reference): opening the Roblox menu (about to
    # leave) tints the whole screen red behind the menu, with big text at the top and bottom
    # where the menu doesn't cover it: what you earn by staying 24 hours vs offline (real
    # numbers, RewardsController), the free potion countdown, and gifts down the sides.
    def big(name, value, pos, h, color, stroke=4, w=0.8):
        return text(name, value, U(w, 0, h, 0), pos, (0.5, 0), ts=60, color=color, display=True, stroke=stroke, TextScaled=True,
                    RichText=True, ZIndex=3, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 90, "MinTextSize": 10})])

    def gift(name, pos, rot, px=150):
        g = icon(name, "Gift", px, pos, (0.5, 0.5), Rotation=rot, ZIndex=2)
        g["properties"]["Size"] = U(0, 0, px / 1080, 0)  # a share of the screen height
        g["children"] = [node("Ratio", "UIAspectRatioConstraint", {"AspectRatio": 1, "DominantAxis": "Height"})]
        return g

    leave = frame("Leave", U(1, 0, 1, 0), bg="#7A0B12", BackgroundTransparency=0.15, ZIndex=1, children=[
        node("Shade", "UIGradient", {"Color": {"keypoints": [[0, "#FF4040"], [0.5, "#5A0610"], [1, "#FF4040"]]}, "Rotation": 90}),
        big("Title", "WAIT! DON'T LEAVE!", U(0.5, 0, 0.02, 0), 0.085, "#FF3B3B", 5, 0.62),
        big("Earn", "YOU'LL EARN <font color=\"#FFD23C\">+$0 COINS</font> EVERY 24 HOURS!", U(0.5, 0, 0.105, 0), 0.05, "#7FE36B", 3.5),
        big("Potion", "STAY 5:00 MORE FOR A FREE LUCK POTION!", U(0.5, 0, 0.16, 0), 0.035, WHITE, 3),
        big("Title2", "WAIT! DON'T LEAVE!", U(0.5, 0, 0.75, 0), 0.1, "#FF3B3B", 5, 0.62),
        big("Offline", "OFFLINE YOU ONLY EARN <font color=\"#FFD23C\">+$0 COINS</font> A DAY", U(0.5, 0, 0.86, 0), 0.055, "#E8E0B0",
            3.5),
        gift("GiftA", U(0.9, 0, 0.22, 0), 12),
        gift("GiftB", U(0.95, 0, 0.5, 0), -10),
        gift("GiftC", U(0.9, 0, 0.78, 0), 8),
        gift("GiftD", U(0.08, 0, 0.3, 0), -14, 120),
        gift("GiftE", U(0.06, 0, 0.7, 0), 10, 120),
    ])
    chip = plate("Chip", U(0, 0, 0, 40), U(0.5, 0, 0, 116), (0.5, 0), BG, stud=0.5, stroke=3, AutomaticSize="X", Visible=False,
                 children=[
                     autoscale(), padding(48, 14, 0),
                     icon("Icon", "PotionLuck", 44, U(0, -46, 0.5, 0), (0, 0.5)),
                     text("Label", "Free potion in 5:00", U(0, 0, 1, 0), ts=19, color=ACCENT, display=True, stroke=2.5,
                          AutomaticSize="X", TextWrapped=False),
                 ])
    write("Stay", screen([chip], order=14))
    leave_screen = screen([leave], order=60, enabled=False, inset=True)
    leave_screen["properties"]["ScreenInsets"] = "None"
    write("Leave", leave_screen)


def rebirth():
    """Rebirth window (Dev, 2026-10-31, from a reference): "Rebirth 4" -> "Rebirth 5" cards with
    what each gives, a Requirements panel with a bar, then Rebirth OR Skip (Robux)."""
    W, H = 660, 432

    def card(name, x, color):
        return button(name, U(0, 250, 0, 108), U(0, x, 0, 78), color=color, stroke=3, Active=False, children=[
            text("Title", "Rebirth 0", U(1, -12, 0, 36), U(0.5, 0, 0, 8), (0.5, 0), ts=30, display=True, stroke=3, ZIndex=4),
            text("Mult", "x1 Cash", U(1, -12, 0, 26), U(0.5, 0, 0, 46), (0.5, 0), ts=22, display=True, stroke=2.5, ZIndex=4),
            text("Extra", "", U(1, -12, 0, 22), U(0.5, 0, 0, 74), (0.5, 0), ts=17, display=True, stroke=2, ZIndex=4,
                 TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 17, "MinTextSize": 8})]),
        ])

    req = plate("Req", U(1, -32, 0, 106), U(0, 16, 0, 198), tint="#3A2A5C", stroke=3, children=[
        text("Title", "Requirements:", U(1, -20, 0, 28), U(0.5, 0, 0, 6), (0.5, 0), ts=24, display=True, stroke=2.5),
        text("Text", "Have $0 (you have $0)", U(1, -20, 0, 26), U(0.5, 0, 0, 34), (0.5, 0), ts=20, display=True, stroke=2,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 20, "MinTextSize": 9})]),
        frame("Bar", U(1, -36, 0, 26), U(0.5, 0, 0, 68), (0.5, 0), bg="#14171D", children=[
            border(INK, 3),
            frame("Fill", U(0.5, 0, 1, 0), bg="#FFB020", children=[
                node("Shade", "UIGradient", {"Color": {"keypoints": [[0, "#FFE066"], [1, "#FF8A1E"]]}, "Rotation": 90}),
            ]),
            text("Pct", "50%", U(1, 0, 1, 0), ts=18, display=True, stroke=2.5, ZIndex=4),
        ]),
    ])
    body = [
        card("Now", 16, "#8FD13F"),
        icon("Arrow", "ArrowDown", 70, U(0.5, 0, 0, 132), (0.5, 0.5), Rotation=-90),
        card("Next", W - 266, "#FFC83C"),
        req,
        text("Info", "Resets cash, tools, cars and the upgrade tree. Keeps pets, index and zones.", U(1, -32, 0, 22),
             U(0.5, 0, 0, 310), (0.5, 0), ts=16, color=SUB, heavy=True),
        button("RebirthButton", U(0, 250, 0, 72), U(0, 16, 1, -14), (0, 1), color=SUCCESS, label="Rebirth", ts=36),
        text("Or", "OR", U(0, 100, 0, 50), U(0.5, 0, 1, -25), (0.5, 0.5), ts=34, color=INK, display=True),
        button("SkipButton", U(0, 250, 0, 72), U(1, -16, 1, -14), (1, 1), color=REBIRTH, label="Skip", ts=36, children=[
            text("Price", "R$ 19", U(0, 90, 0, 30), U(1, 12, 0, -14), (1, 0), ts=24, color="#B6FF5C", display=True, stroke=3,
                 Rotation=8, ZIndex=6),
            text("Sub", "[30% saved needed]", U(1, -10, 0, 20), U(0.5, 0, 1, 12), (0.5, 1), ts=16, color=PREMIUM, display=True,
                 stroke=2.5, ZIndex=6),
        ]),
    ]
    write("Rebirth", screen([dim(), window(W, H, "Rebirth", "Rebirth", body, header=REBIRTH, size=(W, H))], order=10, enabled=False))


# ---------------------------------------------------------------- NPC dialog
def dialog():
    """Talking to an NPC (DialogController, used by the Pet Trader). Our own window instead
    of Roblox's Dialog bubbles: the speaker's name on a yellow tab, what they say (typed
    out), and up to four answers as buttons. DialogController resizes the window to fit the
    line and the number of answers (Dev: one button left a big empty gap), so the sizes
    here are only the starting layout."""
    W, H = 420, 120
    option = button("Template", U(0, 0, 0, 0), color=BG, label="", ts=15, stroke=2.5, Visible=False)
    win = frame("Window", U(0, W, 0, H), U(0.5, 0, 1, -112), (0.5, 1), bg=SURFACE, children=[
        autoscale(), border(INK, 3),
        frame("NameTab", U(0, 150, 0, 28), U(0, 12, 0, -18), bg=PREMIUM, ZIndex=3, children=[
            border(INK, 2.5),
            text("Label", "Pet Trader", U(1, -10, 1, 0), U(0, 5, 0, 0), ts=16, color=INK, display=True, ZIndex=4),
        ]),
        text("Text", "", U(1, -28, 0, 40), U(0, 14, 0, 18), ts=16, color=INK, heavy=True, xa="Left", ya="Top"),
        node("Skip", "TextButton", base(U(1, 0, 0, 60), BackgroundTransparency=1, Text="", ZIndex=2)),
        frame("Options", U(1, -24, 0, 36), U(0, 12, 1, -12), (0, 1), children=[
            node("Layout", "UIGridLayout", {"CellSize": U(0.5, -4, 0, 36), "CellPadding": U(0, 8, 0, 8),
                                            "HorizontalAlignment": "Center", "SortOrder": "LayoutOrder"}),
            option,
        ]),
    ])
    write("Dialog", screen([win], order=9, enabled=False))


def confirm():
    """Are-you-sure popup (ConfirmController), e.g. before using a potion from the bag. Opens
    over the bag without closing it."""
    win = window(460, 350, "Use item?", "Potion", popup=True, children=[
        icon("Big", "Potion", 96, U(0.5, 0, 0, 66), (0.5, 0)),
        text("Name", "", U(1, -40, 0, 34), U(0.5, 0, 0, 164), (0.5, 0), ts=28, color=INK, display=True,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 28, "MinTextSize": 14})]),
        text("Text", "", U(1, -40, 0, 44), U(0.5, 0, 0, 200), (0.5, 0), ts=18, color=SUB, heavy=True,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 18, "MinTextSize": 11})]),
        button("Yes", U(0, 190, 0, 56), U(0.5, -100, 1, -16), (0.5, 1), color=SUCCESS, label="Use", ts=28),
        button("No", U(0, 190, 0, 56), U(0.5, 100, 1, -16), (0.5, 1), color=DANGER, label="Cancel", ts=26),
    ])
    write("Confirm", screen([dim(), win], order=14, enabled=False))


def pet_info():
    """A pet's info card (PetInfoController), opened by tapping a pet in the Pets panel: the
    pet turning in a viewport, name in its rarity colour, rarity and weight, cash per second,
    its mutation, and its passive."""
    line = lambda name, y, ts, color: text(name, "", U(1, -228, 0, ts + 8), U(0, 212, 0, y), ts=ts, color=color, display=True,
                                           xa="Left", TextScaled=True,
                                           children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": ts, "MinTextSize": 8})])
    win = window(460, 350, "Pet Info", "Alien", popup=True, children=[
        plate("Stage", U(0, 186, 0, 186), U(0, 14, 0, 76), tint="#2E3340", stroke=3, children=[
            node("Viewport", "ViewportFrame", base(U(1, -8, 1, -8), U(0.5, 0, 0.5, 0), (0.5, 0.5), BackgroundTransparency=1,
                                                   Ambient="#C8D0E8", LightColor=WHITE, LightDirection=[-1, -1, -1], ZIndex=2)),
        ]),
        line("Name", 78, 28, INK),  # rarity colour, outlined (grey Common text on white was faint)
        line("Rarity", 114, 19, SUB),
        line("Income", 144, 22, "#1E9E3A"),
        line("Mutation", 176, 18, SUB),
        plate("PassiveBox", U(1, -28, 0, 70), U(0, 14, 0, 272), tint="#E3F8E6", stroke=3, children=[
            icon("Icon", "Star", 40, U(0, 8, 0.5, 0), (0, 0.5)),
            text("Title", "Passive", U(1, -64, 0, 26), U(0, 56, 0, 6), ts=20, color=INK, display=True, xa="Left",
                 TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 20, "MinTextSize": 8})]),
            text("Text", "", U(1, -64, 0, 28), U(0, 56, 0, 34), ts=18, color="#1E9E3A", display=True, xa="Left",
                 TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 18, "MinTextSize": 8})]),
        ]),
        button("Action", U(0, 180, 0, 50), U(1, -14, 0, 214), (1, 0), color=DANGER, label="Unequip", ts=22),
    ])
    name = next(c for c in win["children"] if c and c.get("name") == "Name")
    name["children"] = [text_stroke(2.5)] + name.get("children", [])
    write("PetInfo", screen([dim(), win], order=13, enabled=False))


# ---------------------------------------------------------------- Offer + Welcome back
def offer():
    # Offer card: slides in next to the left rail (OfferController places it), with what you
    # get as big icons on spinning rays, a tilted sticker and a green Robux button.
    item = frame("Template", U(0, 100, 0, 106), Visible=False, children=[
        icon("Icon", "Star", 64, U(0.5, 0, 0, 0), (0.5, 0)),
        text("Caption", "", U(1, 0, 0, 40), U(0.5, 0, 1, 0), (0.5, 1), ts=18, display=True, stroke=2.5, ZIndex=4,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 18, "MinTextSize": 12})]),
    ])
    win = plate("Window", U(0, 340, 0, 244), U(0, 210, 0.5, -30), (0, 0.5), SURFACE, children=[
        autoscale(),
        node("Rays", "ImageLabel", base(U(0, 280, 0, 280), U(0.5, 0, 0, 96), (0.5, 0.5), BackgroundTransparency=1,
                                        Image=img("Rays"), ImageColor3=PREMIUM, ImageTransparency=0.35, ZIndex=1)),
        plate("Header", U(1, 0, 0, 42), tint=PREMIUM, children=[
            icon("Icon", "Gift", 34, U(0, 6, 0.5, 0), (0, 0.5)),
            text("Title", "Offer", U(1, -96, 1, -6), U(0, 46, 0.5, 0), (0, 0.5), ts=24, display=True, stroke=3, xa="Left",
                 TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 24, "MinTextSize": 12})]),
        ]),
        button("Close", U(0, 38, 0, 38), U(1, -4, 0, 4), (0.5, 0.5), color=DANGER, label="X", ts=22, ZIndex=6),
        frame("Tag", U(0, 112, 0, 28), U(0, -10, 0, -27), bg=DANGER, Rotation=-6, ZIndex=6, children=[
            border(INK, 3),
            text("Label", "BEST DEAL!", U(1, -6, 1, 0), U(0, 3, 0, 0), ts=16, display=True, stroke=2, ZIndex=7,
                 TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 16, "MinTextSize": 8})]),
        ]),
        frame("Items", U(1, -12, 0, 106), U(0.5, 0, 0, 48), (0.5, 0), ZIndex=3, children=[hlist(6, "Center", "Center"), item]),
        text("Text", "", U(1, -24, 0, 24), U(0.5, 0, 0, 156), (0.5, 0), ts=17, color=INK, heavy=True, ZIndex=3,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 17, "MinTextSize": 12})]),
        button("Buy", U(1, -28, 0, 48), U(0.5, 0, 1, -10), (0.5, 1), color=SUCCESS, label="", ts=26, ZIndex=3),
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

    # Floating "+$4.2K" cash pops (OfferController clones Template for each gain): big green
    # text with a dark outline and a small line under it saying where the cash came from.
    pop = frame("Template", U(0, 420, 0, 96), U(0.5, 0, 0.36, 0), (0.5, 0.5), Visible=False, children=[
        autoscale(),
        node("Pop", "UIScale", {"Scale": 1}),
        text("Amount", "+$0", U(1, 0, 0, 70), U(0.5, 0, 0, 0), (0.5, 0), ts=64, color="#5CFF6E", display=True,
             children=[node("TextStroke", "UIStroke", {"Color": "#0E4A17", "Thickness": 4, "ApplyStrokeMode": "Contextual",
                                                       "LineJoinMode": "Miter"})]),
        text("Source", "", U(1, 0, 0, 26), U(0.5, 0, 0, 68), (0.5, 0), ts=22, heavy=True, stroke=2.5),
    ])
    write("Gained", screen([pop], order=13, enabled=True))


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
    # What hatched: outlined text on a dark plate centred above the hotbar (HatchController sets the
    # exact height). The pet goes to your park or bag by itself.
    # Dev (2026-10-29): the card sits on a solid dark plate, not see-through.
    card = plate("Card", U(0, 560, 0, 118), U(0.5, 0, 1, -120), (0.5, 1), tint=BG, Visible=False, ZIndex=4, children=[
        autoscale(),
        text("Rarity", "LEGENDARY", U(1, 0, 0, 22), U(0.5, 0, 0, 0), (0.5, 0), ts=20, display=True, stroke=2.5, ZIndex=5),
        text("Name", "", U(1, 0, 0, 46), U(0.5, 0, 0, 20), (0.5, 0), ts=40, display=True, stroke=3.5, ZIndex=5, TextScaled=True,
             children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 40, "MinTextSize": 14})]),
        text("Info", "", U(1, 0, 0, 26), U(0.5, 0, 0, 66), (0.5, 0), ts=21, heavy=True, stroke=2.5, ZIndex=5, RichText=True),
        text("New", "NEW!", U(0, 90, 0, 30), U(1, -20, 0, 10), (1, 0), ts=26, color=PREMIUM, display=True, stroke=3,
             Rotation=8, Visible=False, ZIndex=6),
        text("Hint", "Click to skip", U(1, 0, 0, 20), U(0.5, 0, 0, 96), (0.5, 0), ts=16, heavy=True, stroke=2, ZIndex=5,
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
        text("Sub", "You're a real World Sweeper now. Here's a gift to get going:", U(1, -40, 0, 44), U(0.5, 0, 0, 72), (0.5, 0),
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
        # Roblox's own feedback prompt (SocialService:PromptFeedbackSubmissionAsync).
        button("Feedback", U(0.5, -20, 0, 52), U(0, 14, 0, 272), color=HEADER, label="Feedback", ts=22, ico="Star", ico_px=32),
        # Codes from social posts (CodesController opens the Codes window). Moved here from
        # the rail (Dev, 2026-10-30: it didn't fit on phones).
        button("Codes", U(0.5, -20, 0, 52), U(1, -14, 0, 272), (1, 0), color="#4C8DFF", label="Codes", ts=22, ico="Gift",
               ico_px=32),
        text("Track", "", U(1, -28, 0, 22), U(0, 14, 1, -12), (0, 1), ts=15, color=SUB, heavy=True),
    ]
    # 370 tall so "Now playing" has its own line under the buttons.
    write("Settings", screen([dim(), window(520, 370, "Settings", "Gear", body, header="#5A6585", scale=1.4)], order=10, enabled=False))


# ---------------------------------------------------------------- Group reward
def group_reward():
    """Free reward window (screen "GroupReward"), opened from the Free pill at the top: just the
    reward and Claim (Dev, 2026-10-31: less text). Claim asks Roblox to join the group first
    when you're not in it. Only group membership is rewarded (Roblox doesn't allow rewards
    for likes or favorites)."""
    def card(name, ico, label, order):
        return plate(name, U(0, 196, 0, 168), tint=WHITE, stud=0.2, LayoutOrder=order, children=[
            icon("Icon", ico, 92, U(0.5, 0, 0, 14), (0.5, 0)),
            text("Label", label, U(1, -12, 0, 40), U(0.5, 0, 1, -8), (0.5, 1), ts=22, color=INK, display=True),
        ])
    # Smaller than the other windows (Dev, 2026-10-31: "make the window smaller").
    title = text("Title", "Join our group for a FREE reward!", U(1, -28, 0, 34), U(0.5, 0, 0, 80), (0.5, 0), ts=24,
                 color=INK, display=True)
    rewards = frame("Rewards", U(1, -28, 0, 168), U(0.5, 0, 0, 122), (0.5, 0), children=[
        hlist(20, "Center", "Center"),
        card("Potions", "PotionLuck", "2 Luck Potions", 1),
        card("Cash", "Cash", "Free Cash", 2),
    ])
    claim = button("Claim", U(0, 280, 0, 64), U(0.5, 0, 0, 308), (0.5, 0), color=SUCCESS, label="Claim", ts=30)
    write("GroupReward", screen([dim(), window(540, 396, "Free Reward", "Gift", [title, rewards, claim], header="#FFB020", size=(540, 396))],
                               order=10, enabled=False))


# ---------------------------------------------------------------- Lucky Wheel
def wheel():
    """Lucky Wheel window (screen "Wheel", WheelController). Left: the wheel. "Spinner"
    turns (its Rotation) and carries the face image and one "Seg<i>" icon + chance per wedge
    (wedge i spans (i-1)*45..i*45 degrees clockwise from the top, like art/wheel_art.py);
    the pointer stays on top. Right, kept simple (Dev, 2026-10-30: the first one was too
    busy): spins you have, the big SPIN button, two Robux spin packs and a "Prize chances"
    button that swaps the packs for the full list of prizes (paid random rewards must show
    their odds)."""
    import math
    size = 400
    segs = []
    for i in range(1, 9):
        a = math.radians((i - 0.5) * 45)
        r = 0.58 * size / 2
        x, y = math.sin(a) * r, -math.cos(a) * r
        segs.append(frame(f"Seg{i}", U(0, 84, 0, 96), U(0.5, round(x, 1), 0.5, round(y, 1)), (0.5, 0.5), Rotation=(i - 0.5) * 45,
                          ZIndex=3, children=[
                              icon("Icon", "Gift", 66, U(0.5, 0, 0, 0), (0.5, 0), ZIndex=4),
                              text("Label", "", U(1, 0, 0, 26), U(0.5, 0, 1, 0), (0.5, 1), ts=20, display=True, stroke=3, ZIndex=5,
                                   TextWrapped=False),
                          ]))
    spinner = frame("Spinner", U(0, size, 0, size), U(0.5, 0, 0.5, 0), (0.5, 0.5), ZIndex=2, children=[
        node("Face", "ImageLabel", base(U(1, 0, 1, 0), BackgroundTransparency=1, Image=img("SpinWheel"), ScaleType="Fit", ZIndex=2)),
    ] + segs)
    area = frame("WheelArea", U(0, 420, 0, 430), U(0, 18, 0, 76), children=[
        spinner,
        node("Pointer", "ImageLabel", base(U(0, 84, 0, 84), U(0.5, 0, 0, -6), (0.5, 0), BackgroundTransparency=1,
                                            Image=img("SpinPointer"), ScaleType="Fit", ZIndex=8)),
    ])

    def buy(name, count, order):
        return button(name, U(0, 170, 0, 78), color=PREMIUM, LayoutOrder=order, children=[
            text("Count", count, U(1, -8, 0, 32), U(0.5, 0, 0, 6), (0.5, 0), ts=24, display=True, stroke=2.5, ZIndex=4),
            text("Price", "", U(1, -8, 0, 30), U(0.5, 0, 1, -6), (0.5, 1), ts=24, display=True, stroke=2.5, ZIndex=4),
        ])

    def odds_row(i):
        return frame(f"Odds{i}", U(0, 160, 0, 38), LayoutOrder=i, children=[
            icon("Icon", "Gift", 34, U(0, 0, 0.5, 0), (0, 0.5)),
            text("Name", "", U(1, -40, 0, 20), U(0, 40, 0, 1), ts=16, color=INK, heavy=True, xa="Left", TextScaled=True,
                 TextWrapped=False, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 16, "MinTextSize": 9})]),
            text("Chance", "", U(1, -40, 0, 18), U(0, 40, 0, 20), ts=16, color=SUB, display=True, xa="Left"),
        ])

    right = frame("Side", U(0, 350, 0, 432), U(1, -14, 0, 76), (1, 0), children=[
        text("Spins", "Spins: 0", U(1, 0, 0, 44), U(0, 0, 0, 0), ts=38, color=INK, display=True),
        text("FreeNote", "", U(1, 0, 0, 26), U(0, 0, 0, 44), ts=19, color=SUB, heavy=True),
        button("SpinButton", U(1, 0, 0, 92), U(0, 0, 0, 82), color=SUCCESS, label="SPIN!", ts=40),
        frame("Buy", U(1, 0, 0, 78), U(0, 0, 0, 200), children=[
            hlist(10, "Center", "Center"),
            buy("Buy1", "+1 Spin", 1), buy("Buy5", "+5 Spins", 2),
        ]),
        plate("Odds", U(1, 0, 0, 196), U(0, 0, 0, 176), tint="#EEF1F7", stroke=3, Visible=False, ZIndex=6, children=[
            frame("List", U(1, -16, 1, -12), U(0, 10, 0, 6), ZIndex=6, children=[
                node("Layout", "UIGridLayout", {"CellSize": U(0, 160, 0, 44), "CellPadding": U(0, 6, 0, 2),
                                                "SortOrder": "LayoutOrder", "FillDirection": "Vertical"}),
            ] + [odds_row(i) for i in range(1, 9)]),
        ]),
        button("OddsButton", U(1, 0, 0, 52), U(0, 0, 1, 0), (0, 1), color="#4C8DFF", label="Prize chances", ts=22, ico="Star",
               ico_px=34),
    ])
    write("Wheel", screen([dim(), window(WIN_W, WIN_H, "Lucky Wheel", "Spin", [area, right], header="#4C8DFF")],
                         order=10, enabled=False))


# ---------------------------------------------------------------- Traveling Merchant
def merchant():
    """Traveling Merchant window (screen "Merchant", MerchantController), opened from the
    prompt on his cart in the plaza. "Timer" says how long he stays; six ware cards
    ("Card1".."Card6", the controller hides the ones you don't have slots for), each with
    an icon (items) or a 3D egg ("Model"), name, rarity, stock left and a Buy button with
    the cash price. "Away" covers the cards while he's gone. "Restock" is the Robux button
    that rolls you a fresh set."""
    def card(i):
        fit = lambda mx, mn: [node("Fit", "UITextSizeConstraint", {"MaxTextSize": mx, "MinTextSize": mn})]
        return plate(f"Card{i}", U(0, 252, 0, 160), tint=WHITE, stroke=3, LayoutOrder=i, children=[
            frame("Stripe", U(0, 8, 1, 0), bg=MUTED, ZIndex=2),
            icon("Icon", "Potion", 66, U(0, 14, 0, 8)),
            node("Model", "ViewportFrame", base(U(0, 66, 0, 66), U(0, 14, 0, 8), BackgroundTransparency=1, Visible=False,
                                               ZIndex=3)),
            text("Name", "", U(1, -94, 0, 26), U(0, 86, 0, 6), ts=19, color=INK, display=True, xa="Left", TextScaled=True,
                 TextWrapped=False, children=fit(19, 10)),
            text("Rarity", "", U(1, -94, 0, 20), U(0, 86, 0, 32), ts=16, color=SUB, display=True, xa="Left"),
            text("Left", "", U(1, -94, 0, 20), U(0, 86, 0, 52), ts=15, color=SUB, heavy=True, xa="Left"),
            text("Info", "", U(1, -22, 0, 30), U(0, 14, 0, 76), ts=13, color=SUB, heavy=True, xa="Left", ya="Top",
                 TextScaled=True, children=fit(14, 8)),
            button("Buy", U(1, -26, 0, 42), U(0.5, 4, 1, -7), (0.5, 1), color=SUCCESS, label="Buy", ts=20),
        ])

    cards = frame("Cards", U(1, -24, 0, 334), U(0, 12, 0, 114), children=[
        node("Layout", "UIGridLayout", {"CellSize": U(0, 252, 0, 160), "CellPadding": U(0, 12, 0, 12), "SortOrder": "LayoutOrder",
                                        "HorizontalAlignment": "Center"}),
    ] + [card(i) for i in range(1, 7)])
    away = frame("Away", U(1, -24, 0, 334), U(0, 12, 0, 114), Visible=False, children=[
        icon("Icon", "Merchant", 120, U(0.5, 0, 0, 20), (0.5, 0)),
        text("Title", "The merchant is away", U(1, 0, 0, 44), U(0.5, 0, 0, 150), (0.5, 0), ts=36, color=INK, display=True),
        text("Back", "Back in 12:00", U(1, 0, 0, 34), U(0.5, 0, 0, 198), (0.5, 0), ts=28, color=SUB, display=True),
        text("Info", "He visits the plaza every 20 minutes with potions, charms and rare eggs.", U(1, -60, 0, 50),
             U(0.5, 0, 0, 240), (0.5, 0), ts=18, color=SUB, heavy=True),
    ])
    body = [
        text("Timer", "", U(1, -40, 0, 34), U(0.5, 0, 0, 74), (0.5, 0), ts=24, color=INK, display=True),
        cards, away,
        button("Restock", U(0, 330, 0, 52), U(0.5, 0, 1, -10), (0.5, 1), color=PREMIUM, label="New wares", ts=22, ico="Merchant",
               ico_px=38),
    ]
    write("Merchant", screen([dim(), window(WIN_W, WIN_H, "Traveling Merchant", "Merchant", body, header="#B5651D")],
                            order=10, enabled=False))


# ---------------------------------------------------------------- Quests
def quests():
    """Quests window (screen "Quests", QuestController), opened from the Quests strip under
    World Cleaned or from the Quest Master's dialog. Two tabs:
      Jobs   the Quest Master's current job: number, text, progress bar, reward, and a
             button that sends you to him (jobs are claimed by talking to him).
      Daily  three rows ("Row1".."Row3": text, bar, reward, Claim) and the bonus row
             (all three claimed = a free spin), with the time until new ones."""
    W, H = 640, 470
    fit = lambda mx, mn: [node("Fit", "UITextSizeConstraint", {"MaxTextSize": mx, "MinTextSize": mn})]
    # Three tabs spread evenly over the window with the same margin on both sides.
    TAB_GAP, TAB_M = 8, 16
    TAB_W = (W - 2 * TAB_M - 2 * TAB_GAP) // 3
    tab_x = [TAB_M + i * (TAB_W + TAB_GAP) for i in range(3)]
    # Quest rows: a text column on the left, then the reward and the button on the right,
    # with clear gaps so nothing runs under anything else (Dev, 2026-10-31).
    BTN_W, REW_W, GAP, PAD = 116, 158, 18, 12
    COL = PAD + BTN_W + GAP + REW_W + GAP + PAD  # width taken off the left column

    def tab(name, label, x):
        return button(name, U(0, TAB_W, 0, 46), U(0, x, 0, 76), color="#4C8DFF", label=label, ts=22, children=[badge(px=24)])

    def progress_bar(name, size, pos):
        return frame(name, size, pos, bg="#D9DEE8", children=[
            border(INK, 3),
            frame("Fill", U(0, 0, 1, 0), bg=SUCCESS),
            text("Label", "0/0", U(1, 0, 1, 0), ts=18, display=True, stroke=2.5, ZIndex=4),
        ])

    def reward_box(name, size, pos, anchor=(0, 0)):
        return plate(name, size, pos, anchor, tint="#FFF4CF", stroke=3, children=[
            icon("Icon", "Cash", 40, U(0, 6, 0.5, 0), (0, 0.5)),
            text("Label", "", U(1, -56, 1, -6), U(0, 50, 0.5, 0), (0, 0.5), ts=17, color=INK, display=True, xa="Left",
                 TextScaled=True, children=fit(17, 8)),
        ])

    job = frame("Job", U(1, -2 * TAB_M, 0, 320), U(0, TAB_M, 0, 134), children=[
        plate("Card", U(1, 0, 0, 230), tint=WHITE, stroke=3, children=[
            frame("Stripe", U(1, 0, 0, 8), bg="#4C8DFF", ZIndex=2),
            icon("Npc", "TreasureMap", 96, U(0, 14, 0, 24)),
            text("Number", "JOB 1", U(1, -140, 0, 26), U(0, 124, 0, 20), ts=20, color="#4C8DFF", display=True, xa="Left"),
            text("Text", "", U(1, -140, 0, 40), U(0, 124, 0, 46), ts=30, color=INK, display=True, xa="Left",
                 TextScaled=True, children=fit(30, 12)),
            progress_bar("Bar", U(1, -140, 0, 34), U(0, 124, 0, 96)),
            text("RewardTitle", "REWARD", U(0, 120, 0, 22), U(0, 124, 0, 146), ts=16, color=SUB, display=True, xa="Left"),
            reward_box("Reward", U(0, 300, 0, 52), U(0, 124, 0, 168)),
        ]),
        text("Hint", "Talk to the Quest Master on your base to claim your reward!", U(1, 0, 0, 24), U(0.5, 0, 0, 240), (0.5, 0),
             ts=17, color=SUB, heavy=True),
        button("Go", U(0, 320, 0, 54), U(0.5, 0, 0, 270), (0.5, 0), color=SUCCESS, label="Go to Quest Master", ts=24,
               ico="Base", ico_px=38),
    ])

    def row(i):
        return plate(f"Row{i}", U(1, 0, 0, 70), tint=WHITE, stroke=3, LayoutOrder=i, children=[
            text("Text", "", U(1, -COL, 0, 28), U(0, PAD, 0, 6), ts=20, color=INK, display=True, xa="Left", TextScaled=True,
                 children=fit(20, 9)),
            progress_bar("Bar", U(1, -COL, 0, 24), U(0, PAD, 0, 38)),
            reward_box("Reward", U(0, REW_W, 0, 50), U(1, -(PAD + BTN_W + GAP), 0.5, 0), (1, 0.5)),
            button("Claim", U(0, BTN_W, 0, 50), U(1, -PAD, 0.5, 0), (1, 0.5), color=SUCCESS, label="Claim", ts=22),
        ])

    daily = frame("Daily", U(1, -2 * TAB_M, 0, 330), U(0, TAB_M, 0, 134), Visible=False, children=[
        frame("List", U(1, 0, 0, 234), children=[vlist(8), padding(2, 2, 2, 0)] + [row(i) for i in (1, 2, 3)]),
        plate("Bonus", U(1, 0, 0, 62), U(0, 0, 0, 240), tint="#4C8DFF", stud=0.3, stroke=3, children=[
            icon("Icon", "Spin", 48, U(0, 8, 0.5, 0), (0, 0.5)),
            text("Text", "Claim all 3 for a FREE SPIN!", U(1, -220, 1, -8), U(0, 64, 0, 4), ts=19, display=True, stroke=2.5,
                 xa="Left", TextScaled=True, children=fit(19, 9)),
            button("Claim", U(0, 140, 0, 46), U(1, -8, 0.5, 0), (1, 0.5), color=PREMIUM, label="Claim", ts=22,
                   label_color=INK),
        ]),
        text("Timer", "New quests in 0:00", U(1, 0, 0, 22), U(0.5, 0, 0, 308), (0.5, 0), ts=17, color=SUB, display=True),
    ])
    # Zones tab (2026-10-31): one row per zone questline ("Row1".."Row5": who, quest, bar,
    # reward, and a Go button that takes you to that zone's quest giver).
    def zone_row(i):
        return plate(f"Row{i}", U(1, 0, 0, 92), tint=WHITE, stroke=3, LayoutOrder=i, children=[
            text("Who", "", U(1, -COL, 0, 20), U(0, PAD, 0, 8), ts=16, color="#4C8DFF", display=True, xa="Left", TextScaled=True,
                 children=fit(16, 8)),
            text("Text", "", U(1, -COL, 0, 24), U(0, PAD, 0, 30), ts=20, color=INK, display=True, xa="Left", TextScaled=True,
                 children=fit(20, 9)),
            progress_bar("Bar", U(1, -COL, 0, 24), U(0, PAD, 0, 60)),
            reward_box("Reward", U(0, REW_W, 0, 50), U(1, -(PAD + BTN_W + GAP), 0.5, 0), (1, 0.5)),
            button("Go", U(0, BTN_W, 0, 50), U(1, -PAD, 0.5, 0), (1, 0.5), color="#4C8DFF", label="Go", ts=22),
        ])

    # The list is padded so row outlines aren't clipped and the scroll bar has its own lane.
    zones = frame("Zones", U(1, -2 * TAB_M, 0, 326), U(0, TAB_M, 0, 132), Visible=False, children=[
        scroller("List", U(1, 0, 1, 0), U(0, 0, 0, 0), [vlist(8), padding(4, 16, 4, 4)] +
                 [zone_row(i) for i in (1, 2, 3, 4, 5)]),
    ])
    body = [tab("JobsTab", "Jobs", tab_x[0]), tab("DailyTab", "Daily", tab_x[1]), tab("ZonesTab", "Zones", tab_x[2]), job, daily, zones]
    write("Quests", screen([dim(), window(W, H, "Quests", "TreasureMap", body, header="#4C8DFF", size=(W, H))],
                          order=10, enabled=False))


# ---------------------------------------------------------------- Codes
def codes():
    """Codes window (screen "Codes", CodesController), opened from the Codes button in
    Settings: a box to type a code from our social posts, a big Redeem button and the result
    under it. Fitted to its content (Dev, 2026-10-31: it was huge for no reason)."""
    W, H = 480, 352
    box = plate("Entry", U(1, -28, 0, 168), U(0, 14, 0, 76), tint=WHITE, stud=0.2, children=[
        text("Title", "ENTER A CODE", U(1, -30, 0, 30), U(0.5, 0, 0, 10), (0.5, 0), ts=28, color=INK, display=True),
        text("Text", "Find codes in our social posts and the group!", U(1, -30, 0, 22), U(0.5, 0, 0, 40), (0.5, 0), ts=16,
             color=SUB, heavy=True),
        node("Input", "TextBox", base(U(1, -40, 0, 58), U(0.5, 0, 0, 68), (0.5, 0), BackgroundColor3="#EEF1F7", Text="",
                                      PlaceholderText="Type code here", PlaceholderColor3="#9AA3B8", TextColor3=INK, TextSize=30,
                                      FontFace=DISPLAY, ClearTextOnFocus=False, TextXAlignment="Center", ZIndex=3,
                                      TextScaled=False), [padding(12, 12, 0), border(INK, 4)]),
        text("Status", "", U(1, -30, 0, 26), U(0.5, 0, 1, -8), (0.5, 1), ts=18, color=SUB, display=True),
    ])
    redeem = button("Redeem", U(0, 280, 0, 62), U(0.5, 0, 0, 254), (0.5, 0), color=SUCCESS, label="Redeem", ts=30)
    note = text("Note", "Each code works once. Some codes run out, so use them fast!", U(1, -28, 0, 22), U(0, 14, 1, -8), (0, 1),
                ts=16, color=SUB, heavy=True)
    write("Codes", screen([dim(), window(W, H, "Codes", "Star", [box, redeem, note], header="#4C8DFF", size=(W, H))],
                         order=10, enabled=False))


# ---------------------------------------------------------------- Garage
def garage():
    """Gear window (screen "Garage", called "Tools" before 2026-10-30): a Tools tab (the tool ladder: buy the next one with
    cash or skip with Robux) and a Cars tab (buy, spawn, Robux unlock / rent, and a button
    that teleports you to the Garage). Opened from the Tools button on the right."""
    # A shop card per tool / car (Dev: the price hid in small text under the name). The
    # price is on the big button itself ("Buy $1.2B"), a pill on the corner says where you
    # stand (Equipped / Owned / Next / Locked), and the three stats sit in a little table.
    def stat(name, label, y):
        return frame(name, U(1, -16, 0, 20), U(0, 8, 0, y), children=[
            text("Label", label, U(0.5, 0, 1, 0), ts=16, color=SUB, heavy=True, xa="Left"),
            text("Value", "", U(0.5, 0, 1, 0), U(1, 0, 0, 0), (1, 0), ts=16, color=INK, display=True, xa="Right"),
        ])
    row = plate("Template", U(0, 0, 0, 0), tint=WHITE, stud=0.2, Visible=False, children=[
        icon("Icon", "Vehicle", 70, U(0.5, 0, 0, 26), (0.5, 0)),
        frame("Status", U(0, 92, 0, 24), U(0, 6, 0, 6), bg=SUCCESS, Visible=False, ZIndex=4, children=[
            border(INK, 2),
            text("Label", "OWNED", U(1, -6, 1, 0), U(0.5, 0, 0, 0), (0.5, 0), ts=16, display=True, stroke=2, ZIndex=5,
                 TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 16, "MinTextSize": 7})]),
        ]),
        text("Name", "Car", U(1, -12, 0, 26), U(0.5, 0, 0, 96), (0.5, 0), ts=21, color=INK, display=True,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 21, "MinTextSize": 10})]),
        stat("Width", "Width", 122),
        stat("Leaves", "Leaves", 142),
        stat("Holds", "Holds", 162),
        button("Main", U(1, -14, 0, 46), U(0.5, 0, 0, 190), (0.5, 0), color=SUCCESS, label="Buy", ts=21),
        button("Robux", U(1, -14, 0, 30), U(0.5, 0, 0, 242), (0.5, 0), color=PREMIUM, label="", ts=16, label_color=INK,
               Visible=False),
    ])
    tabs = frame("Tabs", U(1, -28, 0, 50), U(0, 14, 0, 76), children=[
        hlist(10, "Left", "Center"),
        button("TabTools", U(0, 170, 0, 46), color="#4C8DFF", label="Tools", ts=22, ico="Tool", ico_px=34, LayoutOrder=1),
        button("TabCars", U(0, 170, 0, 46), color="#FF9A3C", label="Cars", ts=22, ico="Vehicle", ico_px=34, LayoutOrder=2),
    ])
    lst = scroller("List", U(1, -28, 1, -206), U(0, 14, 0, 134), [
        node("Layout", "UIGridLayout", {"CellSize": U(0, 182, 0, 282), "CellPadding": U(0, 10, 0, 10), "SortOrder": "LayoutOrder",
                                        "HorizontalAlignment": "Left"}),
        padding(4, 4, 4, 6), row])
    hint = text("Hint", "", U(1, -28, 0, 44), U(0, 14, 1, -12), (0, 1), ts=15, color=SUB, heavy=True, xa="Left")
    write("Garage", screen([dim(), window(WIN_W, WIN_H, "Gear", "Tools", [tabs, lst, hint], header="#4C8DFF")],
                           order=10, enabled=False))


# ---------------------------------------------------------------- Base picker
def base_picker():
    """Base skins (BasePickerController). Opened from the "Change Base" sign at your base:
    a window with one card per base (picture, name, where you stand). Tapping a card closes
    it, shows that skin on your base with the camera on it, and opens the bar above the
    hotbar: what it needs (ticks for rebirths and Index, a tile per pet), < > to flip
    through bases, and one button (Unlock / Equip / Equipped / Locked)."""
    card = plate("Template", U(0, 0, 0, 0), tint=WHITE, stud=0.2, Visible=False, children=[
        node("Image", "ImageLabel", base(U(1, -12, 0, 118), U(0.5, 0, 0, 6), (0.5, 0), BackgroundColor3="#2A3260",
                                         ScaleType="Crop", ZIndex=2)),
        frame("Status", U(0, 104, 0, 26), U(0, 4, 0, 4), bg=SUCCESS, ZIndex=4, children=[
            border(INK, 2),
            text("Label", "OWNED", U(1, -6, 1, 0), U(0.5, 0, 0, 0), (0.5, 0), ts=16, display=True, stroke=2, ZIndex=5,
                 TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 16, "MinTextSize": 7})]),
        ]),
        text("Name", "Base", U(1, -12, 0, 28), U(0.5, 0, 0, 130), (0.5, 0), ts=21, color=INK, display=True,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 21, "MinTextSize": 10})]),
        text("Sub", "", U(1, -12, 0, 22), U(0.5, 0, 0, 160), (0.5, 0), ts=16, color=SUB, heavy=True,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 16, "MinTextSize": 8})]),
        node("Hit", "TextButton", base(U(1, 0, 1, 0), BackgroundTransparency=1, Text="", AutoButtonColor=False, ZIndex=6)),
    ])
    lst = scroller("List", U(1, -28, 1, -128), U(0, 14, 0, 116), [
        node("Layout", "UIGridLayout", {"CellSize": U(0, 182, 0, 194), "CellPadding": U(0, 12, 0, 12), "SortOrder": "LayoutOrder",
                                        "HorizontalAlignment": "Left"}),
        padding(4, 4, 4, 6), card])
    hint = text("Hint", "Tap a base to try it on", U(1, -28, 0, 34), U(0, 14, 0, 74), ts=20, color=SUB, heavy=True, xa="Left")
    write("BasePicker", screen([dim(), window(WIN_W, WIN_H, "Change Base", "Base", [hint, lst], header="#F28C28")],
                               order=10, enabled=False))

    bar_ = plate("Bar", U(0, 680, 0, 184), U(0.5, 0, 1, -112), (0.5, 1), BG, stud=0.5, children=[
        autoscale(),
        button("Prev", U(0, 46, 0, 110), U(0, 8, 0.5, 0), (0, 0.5), color="#4C8DFF", label="<", ts=30),
        button("Next", U(0, 46, 0, 110), U(1, -8, 0.5, 0), (1, 0.5), color="#4C8DFF", label=">", ts=30),
        text("Title", "Base", U(1, -300, 0, 32), U(0, 64, 0, 8), ts=26, display=True, stroke=2.5, xa="Left",
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 26, "MinTextSize": 12})]),
        text("Status", "", U(1, -300, 0, 22), U(0, 64, 0, 40), ts=17, color=ACCENT, heavy=True, stroke=2, xa="Left",
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 17, "MinTextSize": 8})]),
        frame("Checks", U(1, -300, 0, 26), U(0, 64, 0, 66), children=[hlist(12, "Left", "Center")]),
        frame("Pets", U(1, -300, 0, 82), U(0, 64, 0, 96), children=[hlist(8, "Left", "Center")]),
        button("Close", U(0, 44, 0, 44), U(1, -62, 0, 8), (1, 0), color=DANGER, label="X", ts=24),
        button("Main", U(0, 168, 0, 60), U(1, -62, 1, -10), (1, 1), color=SUCCESS, label="Unlock", ts=22),
    ])
    write("BasePreview", screen([bar_], order=8, enabled=False))


# ---------------------------------------------------------------- Upgrades
HEX_W, HEX_H = 130, 150  # one tree node (HexTile is pointy-top, 0.866 wide)


def upgrades():
    """Upgrade tree, Slime RNG style: full screen over the dimmed world, a honeycomb of hexagon
    nodes (icon, name and price inside), a big title on top and CLOSE at the bottom. Tap a hex
    to buy it; Lab hexes open their own sub-tree (BACK returns). UpgradeController builds the
    boards from Config/Upgrades by cloning Board.Scaler.Canvas.NodeTemplate."""
    fit = lambda mx, mn=9: node("Fit", "UITextSizeConstraint", {"MaxTextSize": mx, "MinTextSize": mn})
    def hexagon(name, radius, color, z, **extra):
        """A pointy-top hexagon from three rotated bars (no image to load, so it always shows)."""
        w = round(radius * 3 ** 0.5, 1)
        bars = [frame(f"Bar{i}", U(0, w, 0, radius), U(0.5, 0, 0.5, 0), (0.5, 0.5), bg=color, Rotation=rot, ZIndex=z)
                for i, rot in enumerate((0, 60, -60))]
        return frame(name, U(0, 0, 0, 0), U(0.5, 0, 0.5, 0), (0.5, 0.5), ZIndex=z, children=bars, **extra)

    node_t = node("NodeTemplate", "TextButton", base(U(0, HEX_W, 0, HEX_H), anchor=(0.5, 0.5), BackgroundTransparency=1,
                                                      Text="", AutoButtonColor=False, Visible=False, ZIndex=3), [
        hexagon("Glow", HEX_H / 2 + 8, SUCCESS, 1, Visible=False),
        hexagon("Outline", HEX_H / 2, INK, 2),
        hexagon("Fill", HEX_H / 2 - 6, "#2A3142", 3),
        # The image tile; UpgradeController shows it (and hides the frame hexagon) once it loads.
        node("Tile", "ImageLabel", base(U(1, 0, 1, 0), BackgroundTransparency=1, Image=img("HexTile"), ScaleType="Fit",
                                        ImageColor3="#2A3142", Visible=False, ZIndex=4), [
            node("Shade", "UIGradient", {"Color": {"keypoints": [[0, WHITE], [0.55, WHITE], [1, "#B9C0CE"]]}, "Rotation": 90}),
        ]),
        text("Level", "0/10", U(0, 70, 0, 18), U(0.5, 0, 0, 14), (0.5, 0), ts=14, color="#E3E8F2", display=True, stroke=2,
             ZIndex=6),
        icon("Icon", "Upgrade", 54, U(0.5, 0, 0, 30), (0.5, 0), ZIndex=5),
        text("Name", "Upgrade", U(1, -22, 0, 24), U(0.5, 0, 0, 84), (0.5, 0), ts=19, display=True, stroke=2.5, ZIndex=6,
             TextScaled=True, children=[fit(19)]),
        frame("Price", U(1, -26, 0, 24), U(0.5, 0, 0, 108), (0.5, 0), ZIndex=6, children=[
            hlist(4, "Center", "Center"),
            icon("Coin", "Cash", 22, ZIndex=6, LayoutOrder=1),
            text("Label", "$0", U(0, 0, 1, 0), ts=19, color=WHITE, display=True, stroke=2.5, ZIndex=7, LayoutOrder=2,
                 AutomaticSize="X", TextWrapped=False),
        ]),
        icon("Lock", "Lock", 52, U(0.5, 0, 0.5, -10), (0.5, 0.5), ZIndex=6, Visible=False),
        text("Question", "?", U(1, 0, 1, 0), ts=72, display=True, stroke=4, ZIndex=6, Visible=False),
    ])
    # Tapping the empty board closes the tooltip.
    backdrop = node("Backdrop", "TextButton", base(U(1, 0, 1, 0), BackgroundTransparency=1, Text="", AutoButtonColor=False,
                                                    ZIndex=0))
    # Tooltip over a hex: hover on PC, first tap on phones (a second tap buys).
    tooltip = frame("Tooltip", U(0, 330, 0, 108), anchor=(0.5, 1), bg="#0B0E1E", BackgroundTransparency=0.12, Visible=False,
                    ZIndex=20, children=[
                        autoscale(),
                        border(INK, 3),
                        text("Name", "", U(1, -16, 0, 26), U(0.5, 0, 0, 6), (0.5, 0), ts=22, display=True, stroke=2.5, ZIndex=21),
                        text("Info", "", U(1, -16, 0, 22), U(0.5, 0, 0, 32), (0.5, 0), ts=16, color="#7CF58A", display=True,
                             stroke=2, ZIndex=21, TextScaled=True, children=[fit(16)]),
                        text("Desc", "", U(1, -16, 0, 20), U(0.5, 0, 0, 55), (0.5, 0), ts=14, color="#C8D0E8", heavy=True,
                             ZIndex=21),
                        text("Hint", "", U(1, -16, 0, 22), U(0.5, 0, 0, 79), (0.5, 0), ts=16, color="#FFD65A", display=True,
                             stroke=2, ZIndex=21),
                    ])
    board = frame("Board", U(1, 0, 1, 0), children=[
        backdrop,
        frame("Scaler", U(0, 0, 0, 0), U(0.5, 0, 0.5, -10), (0.5, 0.5), children=[
            autoscale(),
            frame("Canvas", U(0, 0, 0, 0), U(0.5, 0, 0.5, 0), (0.5, 0.5), children=[
                node("Zoom", "UIScale", {"Scale": 1}),
                node_t,
            ]),
        ]),
    ])
    top = frame("Top", U(0, 900, 0, 84), U(0.5, 0, 0, 6), (0.5, 0), children=[
        autoscale(),
        text("Title", "Upgrades!", U(1, 0, 1, 0), ts=54, display=True, stroke=4),
        # Tutorial line under the title ("Double-tap Sweep Power to buy it!").
        text("Hint", "", U(1, 0, 0, 30), U(0.5, 0, 1, 2), (0.5, 0), ts=26, color="#FFD65A", display=True, stroke=3,
             Visible=False),
    ])
    bottom = frame("Bottom", U(0, 900, 0, 196), U(0.5, 0, 1, -8), (0.5, 1), children=[
        autoscale(),
        button("Close", U(0, 250, 0, 88), U(0.5, 0, 1, 0), (0.5, 1), color=DANGER, label="CLOSE", ts=46, ZIndex=5),
        button("Back", U(0, 170, 0, 72), U(0.5, -140, 1, -8), (1, 1), color=HEADER, label="BACK", ts=32, ZIndex=5,
               Visible=False),
        button("ZoomOut", U(0, 64, 0, 64), U(0.5, 140, 1, -12), (0, 1), color=HEADER, label="-", ts=40, ZIndex=5),
        button("ZoomIn", U(0, 64, 0, 64), U(0.5, 214, 1, -12), (0, 1), color=HEADER, label="+", ts=40, ZIndex=5),
    ])
    d = dim()
    d["className"] = "Frame"
    for k in ("Text", "AutoButtonColor"):
        d["properties"].pop(k, None)
    d["properties"]["BackgroundTransparency"] = 0.45
    write("Upgrades", screen([d, board, top, bottom, tooltip], order=10, enabled=False))


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
        # Skip (LoadingController shows it after a moment): drops you in right away.
        frame("SkipHolder", U(0, 200, 0, 70), U(1, -24, 1, -24), (1, 1), children=[
            autoscale(),
            button("Skip", U(1, 0, 1, 0), color=SUCCESS, label="Skip", ts=28, Visible=False, ZIndex=5),
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
    dialog()
    confirm()
    pet_info()
    hover()
    rewards()
    rebirth()
    offer()
    hatch()
    settings()
    tutorial_done()
    garage()
    base_picker()
    group_reward()
    wheel()
    codes()
    quests()
    merchant()
    upgrades()
    loading()
    print("ui written to", OUT)


if __name__ == "__main__":
    main()
