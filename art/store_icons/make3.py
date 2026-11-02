"""Store icons v3: transparent PNGs for every game pass and dev product.

Roblox shows these inside a round mask, so there is no background card and
everything (icon, xN label, small badge) stays inside the middle ~70% square
(77..435 px of 512), which fits inside the circle.

Run in a folder holding icons/<Icon_*>.png (fetched from Open Cloud), then
push with push2.py (it reads plan2.json and out/).
"""
import re, os, json
from PIL import Image, ImageDraw, ImageFont, ImageOps
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT = f"{ROOT}/art/blender/fonts/Montserrat-Black.ttf"
P = open(f"{ROOT}/src/shared/Config/Products.luau").read()
TOOLS = dict(re.findall(r'Tier = (\d+), Id = "(\w+)"', open(f"{ROOT}/src/shared/Config/Tools.luau").read()))
RAR = {"Common":(200,205,215),"Uncommon":(90,220,110),"Rare":(70,160,255),"Epic":(155,107,255),"Legendary":(255,194,46),"Mythic":(255,75,85),"Cosmic":(60,90,220),"Halloween":(255,130,30)}
ITEM = {"WeatherTotem":"Icon_WeatherTotem","LeafBomb":"Icon_LeafBomb","LuckyClover":"Icon_LuckyClover","LuckPotion":"Icon_PotionLuck",
  "CashPotion":"Icon_PotionCash","MutationSpray":"Icon_MutationSpray","SuperLuckPotion":"Icon_PotionSuperLuck","MegaCashPotion":"Icon_PotionMegaCash","HugeCharm":"Icon_HugeCharm"}
PASS = {"Cash2x":("Icon_Cash","2x"),"AutoSweep":("Icon_Auto",None),"ExtraSlots":("Icon_Base","+3"),"Carry3":("Icon_Egg","x3"),"VIP":("Icon_Star","VIP"),
  "FasterHatch":("Icon_Timer","2x"),"FastWalk":("Icon_Speed",None),"BigBag":("Icon_Backpack","2x"),"Lucky":("Icon_LuckyClover",None),"SellAnywhere":("Icon_Sell",None)}
S = 512; LO, HI = 77, 435  # safe square
def load(n): return Image.open(f"icons/{n}.png").convert("RGBA")
def tint(im, col):
    g = ImageOps.grayscale(im.convert("RGB"))
    t = ImageOps.colorize(g, (0,0,0), col, mid=tuple(int(c*0.75) for c in col)).convert("RGBA")
    t.putalpha(im.getchannel("A")); return t
def fit(im, box):
    a = im.getchannel("A").point(lambda v: 255 if v > 8 else 0); im = im.crop(a.getbbox())
    k = box / max(im.size); return im.resize((max(1,round(im.width*k)), max(1,round(im.height*k))), Image.LANCZOS)
def card(icon, label=None, badge=None):
    c = Image.new("RGBA", (S,S), (0,0,0,0))
    big = label is None and badge is None
    ic = fit(icon, 358 if big else 300)
    cx, cy = (256, 256) if big else (256, 236)
    c.alpha_composite(ic, (cx - ic.width//2, cy - ic.height//2))
    if badge is not None:
        b = fit(badge, 140); c.alpha_composite(b, (LO + 4, HI - b.height - 4))
    if label:
        f = ImageFont.truetype(FONT, 110 if len(label) <= 2 else 88)
        d = ImageDraw.Draw(c); l, t, r, btm = d.textbbox((0,0), label, font=f, stroke_width=12)
        d.text((HI - r, HI - btm), label, font=f, fill=(255,255,255), stroke_width=12, stroke_fill=(20,20,28))
    return c
os.makedirs("out", exist_ok=True)
egg = load("Icon_Egg"); gift = load("Icon_Gift"); timer = load("Icon_Timer")
plan = {}
for m in re.finditer(r'\{ Key = "(\w+)", Id = (\d+), Price = \d+, Name = "([^"]*)"([^\n]*)', P):
    key, pid, name, rest = m.groups()
    kind = re.search(r'Kind = "(\w+)"', rest); kind = kind and kind[1]
    cnt = re.search(r'Count = (\d+)', rest); cnt = int(cnt[1]) if cnt else 1
    xl = f"x{cnt}" if cnt > 1 else None
    if kind is None:  # game pass
        ic, lab = PASS[key]; img = card(load(ic), lab); plan[key] = (pid, name, "pass")
        img.save(f"out/{key}.png"); continue
    if kind == "EggPack":
        img = card(tint(egg, RAR[re.search(r'Rarity = "(\w+)"', rest)[1]]), xl)
    elif kind == "LimitedEgg":
        img = card(tint(egg, RAR["Halloween"]), xl)
    elif kind == "SkipHatch":
        img = card(tint(egg, RAR[key.replace("SkipHatch", "")]), None, timer)
    elif kind == "ItemPack":
        img = card(load(ITEM[re.search(r'Item = "(\w+)"', rest)[1]]), xl)
    elif kind == "ToolSkip":
        img = card(load(f"Icon_Tool_{TOOLS[re.search(r'Tier = (\d+)', rest)[1]]}"))
    elif kind in ("VehicleUnlock", "VehicleRental"):
        car = key.replace("Unlock", "").replace("Rent", "")
        img = card(load(f"Icon_Car_{car}"), None, timer if kind == "VehicleRental" else None)
    elif kind == "GiftPass":
        ic, lab = PASS[key.replace("Gift", "")]; img = card(load(ic), lab, gift)
    elif kind == "StarterPack":
        img = card(gift, None, load("Icon_Star"))
    elif kind == "ServerLuck":
        img = card(load("Icon_Luck"), re.search(r'Mult = (\d+)', rest)[1] + "x")
    elif kind == "MeteorShower":
        img = card(load("Icon_Meteor"))
    elif kind == "CashPack":
        img = card(load("Icon_Cash"))
    elif kind == "SkipRebirth":
        img = card(load("Icon_Rebirth"))
    elif kind == "WheelSpins":
        img = card(load("Icon_Spin"), xl)
    elif kind == "MerchantRestock":
        img = card(load("Icon_Merchant"))
    elif kind == "DoubleOffline":
        img = card(timer, "2x")
    else:
        print("skip", key, kind); continue
    img.save(f"out/{key}.png"); plan[key] = (pid, name, "product")
json.dump(plan, open("plan2.json", "w"), indent=1); print(len(plan))
# preview: each icon inside Roblox's round mask on the store's dark card
ks = list(plan); cols = 12; T = 140
sheet = Image.new("RGB", (cols*T, ((len(ks)+cols-1)//cols)*T), (36,37,40))
mask = Image.new("L", (T-12, T-12), 0); ImageDraw.Draw(mask).ellipse([0, 0, T-13, T-13], fill=255)
for i, k in enumerate(ks):
    tile = Image.new("RGBA", (T-12, T-12), (50,52,56,255))
    tile.alpha_composite(Image.open(f"out/{k}.png").resize((T-12, T-12), Image.LANCZOS))
    sheet.paste(tile.convert("RGB"), ((i%cols)*T+6, (i//cols)*T+6), mask)
sheet.save("sheet3.png")
