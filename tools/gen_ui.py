"""Writes src/gui/*.model.json: every ScreenGui in the game, in the stud style from
docs/UI_STYLE.md (white spacesuit stud panels, blue stud headers, thick navy outline).

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
BG = "#141A33"        # night navy: dim overlay, dark plates
SURFACE = "#E9EEF7"   # spacesuit white stud panels
HEADER = "#3B4FA8"    # header stud strip
INK = "#1B1F3A"       # outline, dark text
SUB = "#4A5170"       # secondary text on white
ACCENT = "#7CF5C8"    # alien mint: selected tab, Moon bar
SUCCESS = "#3DDC5A"   # buy with cash, claim, go
PREMIUM = "#FFC83C"   # Robux, rare
DANGER = "#FF4D5E"    # close, full
MUTED = "#A6AEC2"     # disabled / owned
WHITE = "#FFFFFF"
PILL_BASE = "#3DDC5A"
PILL_SELL = "#FF9A3C"
PILL_ZONES = "#4C8DFF"
REBIRTH = "#9B6BFF"

RADIUS = 0  # square corners everywhere (Dev: rounded corners looked bad)
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


def studs(tint, transparency=0, tile=STUD_TILE, r=RADIUS):
    return node("Studs", "ImageLabel", base(U(1, 0, 1, 0), BackgroundTransparency=1, Image=img("Stud"), ScaleType="Tile",
                                           TileSize=U(0, tile, 0, tile), ImageColor3=tint, ImageTransparency=transparency, ZIndex=0),
                [corner(r)])


def plate(name, size, pos=U(0, 0, 0, 0), anchor=(0, 0), tint=SURFACE, children=None, stud=0, r=RADIUS, stroke=STROKE, **extra):
    """Stud panel: tinted stud texture, thick navy outline, one corner radius."""
    kids = [corner(r), border(INK, stroke) if stroke else None]
    if stud is not None:
        kids.append(studs(tint, stud, r=r))
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
    return node(name, "ImageLabel", base(U(0, px, 0, px), pos, anchor, BackgroundTransparency=1, Image=img(image),
                                         ScaleType="Fit", ZIndex=3, **extra))


def button(name, size, pos=U(0, 0, 0, 0), anchor=(0, 0), color=SUCCESS, label=None, ts=24, label_color=WHITE,
           ico=None, ico_px=36, children=None, stud=None, r=RADIUS, stroke=STROKE, dark="#BCC4D4", **extra):
    """A raised button: colour fill, navy outline, lighter top edge, optional icon + label.
    Controllers set text through the child Label (Ui.setText)."""
    kids = [corner(r), border(INK, stroke) if stroke else None, shine(dark)]
    if stud is not None:
        kids.append(studs(color, stud, r=r))
    if ico:
        kids.append(icon("Icon", ico, ico_px, U(0, 8, 0.5, 0), (0, 0.5)))
    if label is not None:
        left = ico_px + 10 if ico else 6
        kids.append(text("Label", label, U(1, -(left + 6), 1, 0), U(0, left, 0, 0), ts=ts, color=label_color, display=True,
                         stroke=2.5 if label_color == WHITE else None, xa="Center" if not ico else "Left"))
    p = base(size, pos, anchor, BackgroundColor3=color, Text="", AutoButtonColor=False, ZIndex=1)
    p.update(extra)
    return node(name, "TextButton", p, kids + (children or []))


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


def window(w, h, title, ico, children, header=HEADER):
    """Modal window: white stud body, coloured stud header strip, red X top-right."""
    return plate("Window", U(0, w, 0, h), U(0.5, 0, 0.5, 0), (0.5, 0.5), SURFACE, [
        autoscale(),
        plate("Header", U(1, 0, 0, 64), tint=header, children=[
            icon("Icon", ico, 64, U(0, -6, 0.5, -2), (0, 0.5)),
            text("Title", title, U(1, -150, 1, 0), U(0, 66, 0, 0), ts=30, display=True, stroke=3, xa="Left"),
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
    return button(name, U(0, 84, 0, 84), color=color, stud=0.15, LayoutOrder=order, children=[
        icon("Icon", ico, 62, U(0.5, 0, 0, 2), (0.5, 0)),
        text("Label", label, U(1, 20, 0, 24), U(0.5, 0, 1, 2), (0.5, 1), ts=17, display=True, stroke=3),
        plate("Badge", U(0, 28, 0, 28), U(1, 6, 0, -6), (1, 0), DANGER, r=14, stroke=3, stud=None, Visible=False, ZIndex=4,
              children=[text("Label", "!", U(1, 0, 1, 0), ts=20, display=True, ZIndex=5)]),
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
    moon = plate("MoonPanel", U(0, 360, 0, 40), U(0.5, 0, 0, 68), (0.5, 0), BG, stud=0.6, children=[
        autoscale(),
        icon("Icon", "Star", 46, U(0, -12, 0.5, 0), (0, 0.5)),
        frame("Bar", U(1, -48, 1, -14), U(0, 38, 0.5, 0), (0, 0.5), bg="#2A3260", children=[
            corner(8),
            frame("Fill", U(0.3, 0, 1, 0), bg=ACCENT, children=[corner(8)]),
        ]),
        text("Label", "Moon Clean 0%", U(1, -48, 1, 0), U(0, 38, 0, 0), ts=19, heavy=True, stroke=2.5, ZIndex=3),
    ])
    # Active boosts (server luck, 2x cash): chips stacked in the bottom-right corner.
    # Phones move them to the top right (HudController), clear of the jump button.
    boosts = frame("Boosts", U(0, 300, 0, 200), U(1, -14, 1, -14), (1, 1), children=[
        autoscale(), vlist(8, "Right", "Bottom"),
        # Short chip: big icon, then "4x 5:00".
        node("Template", "TextLabel", base(U(0, 0, 0, 46), BackgroundColor3=BG, Text="", TextColor3=WHITE, TextSize=24, FontFace=DISPLAY,
                                          AutomaticSize="X", Visible=False, ZIndex=2),
             [corner(), border(INK, 3), padding(50, 12, 0), text_stroke(2.5),
              icon("Icon", "Luck", 52, U(0, -52, 0.5, 0), (0, 0.5))]),
    ])
    toasts = frame("Toasts", U(0, 520, 0, 200), U(0.5, 0, 0, 156), (0.5, 0), children=[
        autoscale(), vlist(6),
        node("Template", "TextLabel", base(U(0, 0, 0, 38), BackgroundColor3=BG, Text="", TextColor3=WHITE, TextSize=20, FontFace=BODY_HEAVY,
                                          AutomaticSize="X", Visible=False, ZIndex=2),
             [corner(), border(INK, 3), padding(14, 14, 0)]),
    ])
    announcement = plate("Announcement", U(0, 0, 0, 64), U(0.5, 0, 0.3, 0), (0.5, 0.5), BG, stud=0.5, AutomaticSize="X", Visible=False,
                         children=[
                             autoscale(), padding(24, 24, 0),
                             text("Text", "", U(0, 0, 1, 0), ts=34, color=PREMIUM, display=True, stroke=3, AutomaticSize="X", TextWrapped=False),
                         ])
    wallet = frame("Wallet", U(0, 270, 0, 130), U(0, 14, 1, -14), (0, 1), children=[
        autoscale(), vlist(10, "Left", "Bottom"),
        plate("CashPanel", U(0, 270, 0, 64), tint=SURFACE, LayoutOrder=1, children=[
            icon("Icon", "Cash", 70, U(0, -10, 0.5, 0), (0, 0.5)),
            text("Cash", "$0", U(1, -120, 0, 38), U(0, 62, 0, 4), ts=28, color=INK, display=True, xa="Left"),
            text("Income", "+$0/s", U(1, -120, 0, 20), U(0, 64, 0, 38), ts=17, color="#1E9E3A", heavy=True, xa="Left"),
            button("PlusButton", U(0, 44, 0, 44), U(1, -10, 0.5, 0), (1, 0.5), color=SUCCESS, label="+", ts=34, stroke=3),
        ]),
        plate("BackpackPanel", U(0, 270, 0, 56), tint=SURFACE, LayoutOrder=2, children=[
            icon("Icon", "Dust", 62, U(0, -8, 0.5, 0), (0, 0.5)),
            frame("Bar", U(1, -78, 0, 28), U(0, 62, 0.5, 0), (0, 0.5), bg=BG, children=[
                corner(8),
                frame("Fill", U(0.2, 0, 1, 0), bg="#E9C98B", children=[corner(8)]),
                text("Amount", "0 / 50", U(1, 0, 1, 0), ts=17, heavy=True, stroke=2.5, ZIndex=3),
            ]),
            plate("Full", U(0, 66, 0, 26), U(1, 4, 0, -12), (1, 0), DANGER, stroke=3, stud=None, Visible=False, ZIndex=4, children=[
                text("Label", "FULL", U(1, 0, 1, 0), ts=18, display=True, stroke=2, ZIndex=5),
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
    bag["children"].append(plate("Badge", U(0, 30, 0, 30), U(1, 6, 0, -6), (1, 0), DANGER, stroke=3, stud=None, Visible=False, ZIndex=5,
                                 children=[text("Label", "!", U(1, 0, 1, 0), ts=18, display=True, ZIndex=6)]))
    hotbar = frame("Hotbar", U(0, 290, 0, 88), U(0.5, 0, 1, -12), (0.5, 1), children=[
        autoscale(), hlist(8, "Center", "Bottom"),
        hot_slot("ToolSlot", "1", "Tool", "Toothbrush", 1),
        hot_slot("CarSlot", "2", "Vehicle", "No car", 2),
        bag,
    ])
    # Tutorial / next-step hint above the hotbar ("Open your bag and place your egg!").
    hint = plate("Hint", U(0, 0, 0, 46), U(0.5, 0, 1, -122), (0.5, 1), BG, stud=0.5, AutomaticSize="X", Visible=False, children=[
        autoscale(), padding(16, 16, 0),
        text("Text", "", U(0, 0, 1, 0), ts=22, color=ACCENT, display=True, stroke=2.5, AutomaticSize="X", TextWrapped=False),
    ])
    # Sweep combo meter (x1.0 - x3.0) above the hint.
    combo = plate("Combo", U(0, 170, 0, 40), U(0.5, 0, 1, -176), (0.5, 1), BG, stud=0.5, Visible=False, children=[
        autoscale(),
        frame("Bar", U(1, -12, 0, 8), U(0.5, 0, 1, -5), (0.5, 1), bg="#2A3260", children=[
            frame("Fill", U(0.5, 0, 1, 0), bg=PREMIUM),
        ]),
        text("Label", "COMBO x1.0", U(1, 0, 1, -10), ts=22, color=PREMIUM, display=True, stroke=2.5),
    ])
    write("Hud", screen([rail, pills, moon, boosts, toasts, announcement, wallet, right, sweep, hotbar, hint, combo, picker], order=1))


# ---------------------------------------------------------------- Shop
def shop_tab(name, label, ico, order):
    return button("Tab" + name, U(1, 0, 0, 54), color=HEADER, label=label, ts=19, ico=ico, ico_px=40, LayoutOrder=order)


def shop():
    tabs = frame("Tabs", U(0, 160, 1, -88), U(0, 14, 0, 76), children=[
        vlist(8),
        shop_tab("Deals", "Deals", "Luck", 1),
        shop_tab("Tools", "Tools", "Tool", 2),
        shop_tab("Eggs", "Eggs", "Egg", 3),
        shop_tab("Passes", "Passes", "Star", 4),
        shop_tab("Cash", "Cash", "Cash", 5),
    ])
    featured = plate("Featured", U(1, -200, 0, 150), U(0, 186, 0, 76), tint=BG, stud=None, Visible=False, children=[
        node("Banner", "ImageLabel", base(U(1, 0, 1, 0), BackgroundTransparency=1, Image=img("BannerStarter"), ScaleType="Crop", ZIndex=1),
             [corner()]),
        text("Title", "Starter Pack", U(0.6, 0, 0, 40), U(0, 16, 0, 12), ts=32, display=True, stroke=3, xa="Left"),
        text("Desc", "", U(0.6, 0, 0, 44), U(0, 16, 0, 54), ts=17, heavy=True, stroke=2.5, xa="Left", ya="Top"),
        button("Buy", U(0, 150, 0, 50), U(1, -14, 1, -14), (1, 1), color=PREMIUM, label="", ts=26, label_color=INK, ZIndex=3),
        plate("Tag", U(0, 120, 0, 28), U(0, 16, 1, -14), (0, 1), DANGER, stroke=3, stud=None, children=[
            text("Label", "ONE TIME", U(1, 0, 1, 0), ts=18, display=True, stroke=2),
        ]),
    ])
    row = plate("Template", U(1, -12, 0, 78), tint=WHITE, stud=0.2, Visible=False, children=[
        icon("Icon", "Tool", 58, U(0, 10, 0.5, 0), (0, 0.5)),
        text("Name", "Item", U(1, -300, 0, 28), U(0, 78, 0, 8), ts=22, color=INK, display=True, xa="Left",
             TextWrapped=False, TextScaled=True,
             children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 22, "MinTextSize": 12})]),
        text("Desc", "", U(1, -300, 0, 34), U(0, 78, 0, 38), ts=15, color=SUB, xa="Left", ya="Top"),
        button("Buy", U(0, 150, 0, 50), U(1, -12, 0.5, 0), (1, 0.5), color=SUCCESS, label="", ts=22),
        button("Gift", U(0, 50, 0, 50), U(1, -172, 0.5, 0), (1, 0.5), color="#FF7EB6", ico="Gift", ico_px=38, Visible=False),
    ])
    lst = scroller("List", U(1, -200, 1, -92), U(0, 186, 0, 80), [vlist(10), padding(2, 2, 4, 4), row])
    empty = text("Empty", "Nothing here right now. Check back soon!", U(1, -200, 0, 60), U(0, 186, 0.5, 0), ts=20, color=SUB, heavy=True,
                 Visible=False)
    gift_row = button("Template", U(1, -10, 0, 46), color=HEADER, label="Player", ts=18, stroke=3, Visible=False)
    gift = plate("GiftPicker", U(0, 380, 0, 330), U(0.5, 0, 0.5, 20), (0.5, 0.5), SURFACE, Visible=False, ZIndex=10, children=[
        plate("Header", U(1, 0, 0, 52), tint="#FF7EB6", children=[
            icon("Icon", "Gift", 54, U(0, -4, 0.5, 0), (0, 0.5)),
            text("Title", "Gift to...", U(1, -110, 1, 0), U(0, 56, 0, 0), ts=28, display=True, stroke=3, xa="Left"),
        ]),
        button("Close", U(0, 44, 0, 44), U(1, -6, 0, 6), (0.5, 0.5), color=DANGER, label="X", ts=26, ZIndex=11),
        scroller("List", U(1, -24, 1, -72), U(0, 12, 0, 62), [vlist(8), padding(2), gift_row]),
        text("Empty", "No one else is here yet.", U(1, -24, 0, 40), U(0, 12, 0.5, 0), ts=18, color=SUB, heavy=True, Visible=False),
    ])
    write("Shop", screen([dim(), window(780, 480, "Shop", "Shop", [tabs, featured, lst, empty, gift], header="#E9A21F")],
                         order=10, enabled=False))


# ---------------------------------------------------------------- Index
def bar(name, size, pos, anchor, fill, label, ts=26):
    return frame(name, size, pos, anchor, bg="#0B0E1E", children=[
        border(INK, 3),
        frame("Fill", U(0.3, 0, 1, 0), bg=fill, children=[studs(fill, 0.3)]),
        text("Label", label, U(1, 0, 1, 0), ts=ts, display=True, stroke=3, ZIndex=4),
    ])


def index():
    """Pet index (Steal an Egg style): a zone panel on the left, rarity-coloured cards,
    the picked pet on the right, zone progress and total progress bars."""
    card = button("Template", U(0, 0, 0, 0), color="#BEBEBE", stud=0.2, stroke=3, Visible=False, children=[
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
            node("Viewport", "ViewportFrame", base(U(1, -16, 0, 200), U(0.5, 0, 0, 8), (0.5, 0), BackgroundTransparency=1,
                                                   Ambient="#C8D0E8", LightColor=WHITE, LightDirection=[-1, -1, -1], ZIndex=2)),
            text("Name", "", U(1, -12, 0, 34), U(0.5, 0, 0, 212), (0.5, 0), ts=26, display=True, stroke=3,
                 TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 26, "MinTextSize": 12})]),
            text("Rarity", "", U(1, -12, 0, 28), U(0.5, 0, 0, 246), (0.5, 0), ts=24, display=True, stroke=3),
            text("Income", "", U(1, -12, 0, 30), U(0.5, 0, 0, 276), (0.5, 0), ts=26, color="#7CFF8C", display=True, stroke=3),
            text("Hint", "", U(1, -16, 0, 60), U(0.5, 0, 1, -8), (0.5, 1), ts=15, color="#E0E4F0", heavy=True, ya="Bottom"),
        ]),
    ])
    total = bar("Total", U(1, -24, 0, 56), U(0, 12, 1, -12), (0, 1), "#4CC3FF", "Unlocked: 0/47", ts=30)
    write("Index", screen([dim(), window(900, 600, "Pet Index", "Index", [body, total], header="#4CC3FF")], order=10, enabled=False))


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
        text("Count", "", U(0, 40, 0, 20), U(1, -4, 0, 2), (1, 0), ts=16, display=True, stroke=2, xa="Right", Visible=False, ZIndex=4),
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
    return button(name, U(0, 80, 0, 80), color=color, stud=0.15, LayoutOrder=order, children=[
        icon("Icon", ico, 64, U(0.5, 0, 0, 0), (0.5, 0)),
        text("Label", label, U(1, 10, 0, 22), U(0.5, 0, 1, 2), (0.5, 1), ts=17, display=True, stroke=2.5),
        plate("Badge", U(0, 30, 0, 30), U(1, 6, 0, -6), (1, 0), DANGER, stroke=3, stud=None, Visible=False, ZIndex=5,
              children=[text("Label", "!", U(1, 0, 1, 0), ts=18, display=True, ZIndex=6)]),
    ])


def list_panel(name, title, head_button, row_children, footer):
    row = plate("Template", U(1, -8, 0, 78), tint="#2A3050", stud=0.6, stroke=3, Visible=False, children=[
        node("Viewport", "ViewportFrame", base(U(0, 70, 0, 70), U(0, 4, 0.5, 0), (0, 0.5), BackgroundTransparency=1,
                                               Ambient="#C8D0E8", LightColor=WHITE, LightDirection=[-1, -1, -1], ZIndex=2)),
        text("Name", "", U(1, -220, 0, 28), U(0, 80, 0, 10), ts=21, display=True, stroke=2.5, xa="Left",
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 21, "MinTextSize": 10})]),
        text("Sub", "", U(1, -220, 0, 24), U(0, 80, 0, 40), ts=18, color="#7CFF8C", display=True, stroke=2, xa="Left"),
    ] + row_children)
    return plate(name, U(0, 400, 0, 430), U(1, -110, 0.5, 0), (1, 0.5), BG, stud=0.55, Visible=False, children=[
        autoscale(),
        plate("Header", U(1, 0, 0, 62), tint=SAND, stud=0.3, children=[
            text("Title", title, U(1, -170, 1, 0), U(0, 14, 0, 0), ts=28, display=True, stroke=3, xa="Left"),
            head_button,
        ]),
        scroller("List", U(1, -16, 1, -146), U(0, 8, 0, 70), [vlist(8), padding(4), row]),
        text("Empty", "", U(1, -30, 0, 80), U(0.5, 0, 0.45, 0), (0.5, 0.5), ts=19, color="#C8D0E8", heavy=True, Visible=False),
        footer,
    ])


def base_panels():
    buttons = frame("Buttons", U(0, 80, 0, 216), U(1, -14, 0.5, -130), (1, 1), children=[
        autoscale(), vlist(28, "Right", "Bottom"),
        side_button("EggsButton", "Eggs", "Egg", DANGER, 1),
        side_button("PetsButton", "Pets", "Alien", "#FF9A3C", 2),
    ])
    active = list_panel(
        "Active", "0/4 Active",
        button("AddSlot", U(0, 140, 0, 44), U(1, -10, 0.5, 0), (1, 0.5), color=DANGER, label="+ Slots", ts=20),
        [button("Action", U(0, 124, 0, 48), U(1, -10, 0.5, 0), (1, 0.5), color=DANGER, label="Unequip", ts=19)],
        button("EquipBest", U(1, -20, 0, 54), U(0.5, 0, 1, -12), (0.5, 1), color=SUCCESS, label="Equip Best", ts=26))
    growing = list_panel(
        "Growing", "Growing Eggs",
        button("OpenAll", U(0, 140, 0, 44), U(1, -10, 0.5, 0), (1, 0.5), color=PREMIUM, label="Open All", ts=20, label_color=INK),
        [button("Action", U(0, 124, 0, 48), U(1, -10, 0.5, 0), (1, 0.5), color=SUCCESS, label="Open", ts=19)],
        button("PlaceEggs", U(1, -20, 0, 54), U(0.5, 0, 1, -12), (0.5, 1), color="#4C8DFF", label="Place Eggs", ts=24))
    write("BasePanels", screen([buttons, active, growing], order=4))


# ---------------------------------------------------------------- Rewards (daily, playtime, group, event)
def reward_card(name, top, order, w, h, ico_px):
    """Daily / gift card: label on top, big icon, reward text, a CLAIMED overlay."""
    return button(name, U(0, w, 0, h), color=WHITE, stud=0.2, stroke=3, LayoutOrder=order, children=[
        text("Day", top, U(1, 0, 0, 24), U(0.5, 0, 0, 2), (0.5, 0), ts=18, color=INK, display=True, ZIndex=4),
        icon("Icon", "Gift", ico_px, U(0.5, 0, 0.5, 2), (0.5, 0.5)),
        text("Reward", "", U(1, -6, 0, 22), U(0.5, 0, 1, -3), (0.5, 1), ts=15, color=INK, display=True, ZIndex=4,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 16, "MinTextSize": 8})]),
        frame("Done", U(1, 0, 1, 0), bg="#0B0E1E", BackgroundTransparency=0.45, Visible=False, ZIndex=6, children=[
            text("Label", "✓", U(1, 0, 1, 0), ts=54, color=SUCCESS, display=True, stroke=3, ZIndex=7),
        ]),
    ])


def rewards():
    days = frame("Days", U(1, -24, 0, 130), U(0, 12, 0, 108), children=[
        hlist(10, "Center", "Center"),
    ] + [reward_card(f"Day{i}", f"Day {i}", i, 92, 124, 66) for i in range(1, 8)])
    group = plate("Group", U(0.5, -18, 0, 84), U(0, 12, 0, 318), tint="#4C8DFF", stud=0.3, stroke=3, children=[
        icon("Icon", "Group", 70, U(0, 4, 0.5, 0), (0, 0.5)),
        text("Text", "Join our group for 2 Luck Potions + cash!", U(1, -220, 1, -8), U(0, 78, 0, 4), ts=16, display=True,
             stroke=2, xa="Left"),
        button("Claim", U(0, 124, 0, 50), U(1, -10, 0.5, 0), (1, 0.5), color=SUCCESS, label="Claim", ts=22),
    ])
    event = plate("Event", U(0.5, -18, 0, 84), U(1, -12, 0, 318), (1, 0), tint="#FF78E6", stud=0.3, stroke=3, children=[
        icon("Icon", "Event", 70, U(0, 4, 0.5, 0), (0, 0.5)),
        text("Name", "Meteor Weekend", U(1, -220, 0, 28), U(0, 78, 0, 6), ts=21, display=True, stroke=2.5, xa="Left",
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 22, "MinTextSize": 10})]),
        text("Info", "", U(1, -220, 0, 44), U(0, 78, 0, 34), ts=14, display=True, stroke=2, xa="Left", ya="Top",
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 15, "MinTextSize": 8})]),
        button("SignUp", U(0, 124, 0, 50), U(1, -10, 0.5, 0), (1, 0.5), color=PREMIUM, label="Sign up", ts=20, label_color=INK),
    ])
    body = [
        text("Streak", "Streak: 0 days", U(1, -32, 0, 30), U(0.5, 0, 0, 72), (0.5, 0), ts=20, color=SUB, heavy=True),
        days,
        button("ClaimDaily", U(0, 280, 0, 52), U(0.5, 0, 0, 250), (0.5, 0), color=SUCCESS, label="Claim Day 1", ts=24),
        group, event,
    ]
    write("Daily", screen([dim(), window(760, 416, "Daily Rewards", "Daily", body, header="#FF5FA2")], order=10, enabled=False))

    # Playtime gifts: their own window (green Gifts button on the rail).
    gifts = frame("Gifts", U(1, -24, 0, 240), U(0, 12, 0, 112), children=[
        node("Layout", "UIGridLayout", {"CellSize": U(0, 140, 0, 112), "CellPadding": U(0, 12, 0, 12), "SortOrder": "LayoutOrder",
                                        "HorizontalAlignment": "Center"}),
    ] + [reward_card(f"Gift{i}", "5:00", i, 140, 112, 64) for i in range(1, 7)])
    gift_body = [
        text("Info", "Free gifts the longer you play! They reset when you rejoin.", U(1, -24, 0, 30), U(0.5, 0, 0, 74), (0.5, 0),
             ts=18, color=SUB, heavy=True),
        gifts,
    ]
    write("Playtime", screen([dim(), window(500, 372, "Playtime Gifts", "Gift", gift_body, header=SUCCESS)], order=10, enabled=False))

    # Stay offer: pops when the player opens the Roblox menu (about to leave).
    stay = plate("Window", U(0, 440, 0, 230), U(0.5, 0, 0.5, 0), (0.5, 0.5), SURFACE, children=[
        autoscale(),
        plate("Header", U(1, 0, 0, 56), tint="#FF5FA2", children=[
            icon("Icon", "PotionLuck", 64, U(0, -6, 0.5, -2), (0, 0.5)),
            text("Title", "Wait! Free potion!", U(1, -130, 1, 0), U(0, 62, 0, 0), ts=28, display=True, stroke=3, xa="Left"),
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
    write("Rebirth", screen([dim(), window(520, 392, "Rebirth", "Rebirth", body, header=REBIRTH)], order=10, enabled=False))


# ---------------------------------------------------------------- Offer + Welcome back
def offer():
    win = plate("Window", U(0, 420, 0, 196), U(0.5, 0, 1, -20), (0.5, 1), SURFACE, children=[
        autoscale(),
        plate("Header", U(1, 0, 0, 42), tint=PREMIUM, children=[
            icon("Icon", "Star", 50, U(0, -6, 0.5, 0), (0, 0.5)),
            text("Title", "Offer", U(1, -110, 1, 0), U(0, 50, 0, 0), ts=26, display=True, stroke=3, xa="Left"),
        ]),
        button("Close", U(0, 44, 0, 44), U(1, -6, 0, 6), (0.5, 0.5), color=DANGER, label="X", ts=26, ZIndex=5),
        text("Text", "", U(1, -28, 0, 70), U(0, 14, 0, 50), ts=18, color=INK, heavy=True, xa="Left", ya="Top"),
        button("Buy", U(0, 200, 0, 52), U(0.5, 0, 1, -12), (0.5, 1), color=PREMIUM, label="", ts=26, label_color=INK),
    ])
    write("Offer", screen([win], order=12, enabled=False))

    welcome = window(460, 350, "Welcome back!", "Cash", [
        icon("Big", "Cash", 96, U(0.5, 0, 0, 72), (0.5, 0)),
        text("Amount", "+$0", U(1, -40, 0, 46), U(0.5, 0, 0, 166), (0.5, 0), ts=40, color="#1E9E3A", display=True),
        text("Text", "", U(1, -40, 0, 40), U(0.5, 0, 0, 218), (0.5, 0), ts=17, color=SUB),
        button("Collect", U(0, 190, 0, 56), U(0.5, -100, 1, -16), (0.5, 1), color=SUCCESS, label="Collect", ts=28),
        button("Double", U(0, 190, 0, 56), U(0.5, 100, 1, -16), (0.5, 1), color=PREMIUM, label="2x", ts=24, label_color=INK),
    ], header=PILL_BASE)
    write("WelcomeBack", screen([dim(), welcome], order=12, enabled=False))


# ---------------------------------------------------------------- Hatch
def hatch():
    stage = frame("Stage", U(0, 560, 0, 560), U(0.5, 0, 0.5, 0), (0.5, 0.5), children=[
        autoscale(),
        node("Glow", "ImageLabel", base(U(1.3, 0, 1.3, 0), U(0.5, 0, 0.45, 0), (0.5, 0.5), BackgroundTransparency=1,
                                        Image="rbxasset://textures/particles/sparkles_main.dds", ImageColor3=ACCENT, ImageTransparency=0.35,
                                        ZIndex=0)),
        node("Viewport", "ViewportFrame", base(U(0, 440, 0, 400), U(0.5, 0, 0, 0), (0.5, 0), BackgroundTransparency=1,
                                               Ambient="#AEB8D8", LightColor=WHITE, LightDirection=[-1, -1, -1], ZIndex=1)),
        text("Name", "", U(1, 0, 0, 56), U(0.5, 0, 0, 396), (0.5, 0), ts=40, display=True, stroke=3.5),
        text("Sub", "", U(1, 0, 0, 30), U(0.5, 0, 0, 452), (0.5, 0), ts=24, heavy=True, stroke=2.5),
        plate("New", U(0, 110, 0, 40), U(0.5, 150, 0, 380), (0.5, 0.5), PREMIUM, stroke=3, stud=None, Rotation=-8, Visible=False, children=[
            text("Label", "NEW!", U(1, 0, 1, 0), ts=26, color=INK, display=True),
        ]),
        text("Hint", "Tap to skip", U(1, 0, 0, 24), U(0.5, 0, 1, -8), (0.5, 1), ts=18, heavy=True, stroke=2, TextTransparency=0.2),
        frame("Choice", U(0, 420, 0, 56), U(0.5, 0, 1, 56), (0.5, 0), Visible=False, children=[
            hlist(16),
            button("Place", U(0, 200, 0, 56), color=SUCCESS, label="Place on base", ts=22, LayoutOrder=1),
            button("Keep", U(0, 180, 0, 56), color=HEADER, label="Keep in bag", ts=22, LayoutOrder=2),
        ]),
    ])
    flash = frame("Flash", U(1, 0, 1, 0), bg=WHITE, BackgroundTransparency=1, ZIndex=10)
    tree = screen([stage, flash], order=20, enabled=False, inset=True)
    tree["properties"]["ScreenInsets"] = "None"
    write("Hatch", tree)


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
    write("Garage", screen([dim(), window(640, 470, "Garage", "Vehicle", [lst, hint], header="#FF9A3C")], order=10, enabled=False))


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
    rewards()
    rebirth()
    offer()
    hatch()
    garage()
    upgrades()
    loading()
    print("ui written to", OUT)


if __name__ == "__main__":
    main()
