import re, os, json
from PIL import Image, ImageDraw, ImageFont, ImageOps
FONT = "/home/user/dev/art/blender/fonts/Montserrat-Black.ttf"
P = open("/home/user/dev/src/shared/Config/Products.luau").read()
TOOLS = dict(re.findall(r'Tier = (\d+), Id = "(\w+)"', open("/home/user/dev/src/shared/Config/Tools.luau").read()))
RAR = {"Common":(200,205,215),"Uncommon":(90,220,110),"Rare":(70,160,255),"Epic":(155,107,255),"Legendary":(255,194,46),"Mythic":(255,75,85),"Cosmic":(60,90,220),"Halloween":(255,130,30)}
BGR = {"Common":(90,96,110),"Uncommon":(30,110,50),"Rare":(25,70,150),"Epic":(70,40,140),"Legendary":(150,95,10),"Mythic":(130,20,40),"Cosmic":(20,25,80),"Halloween":(60,20,80)}
ITEM = {"WeatherTotem":"Icon_WeatherTotem","LeafBomb":"Icon_LeafBomb","LuckyClover":"Icon_LuckyClover","LuckPotion":"Icon_PotionLuck",
  "CashPotion":"Icon_PotionCash","MutationSpray":"Icon_MutationSpray","SuperLuckPotion":"Icon_PotionSuperLuck","MegaCashPotion":"Icon_PotionMegaCash","HugeCharm":"Icon_HugeCharm"}
PASS = {"Cash2x":("Icon_Cash","2x"),"AutoSweep":("Icon_Auto",None),"ExtraSlots":("Icon_Base","+3"),"Carry3":("Icon_Egg","x3"),"VIP":("Icon_Star","VIP"),
  "FasterHatch":("Icon_Timer","2x"),"FastWalk":("Icon_Speed",None),"BigBag":("Icon_Backpack","2x"),"Lucky":("Icon_LuckyClover",None),"SellAnywhere":("Icon_Sell",None)}
C = dict(item=(40,110,70), pass_=(40,110,170), gift=(200,60,120), boost=(120,60,200), tool=(40,80,140), car=(200,110,30), cash=(30,130,60), rebirth=(160,40,90), spin=(30,140,160))
def load(n): return Image.open(f"icons/{n}.png").convert("RGBA")
def tint(im, col):
    g = ImageOps.grayscale(im.convert("RGB"))
    t = ImageOps.colorize(g, (0,0,0), col, mid=tuple(int(c*0.75) for c in col)).convert("RGBA")
    t.putalpha(im.getchannel("A")); return t
def fit(im, box):
    a = im.getchannel("A").point(lambda v: 255 if v > 8 else 0); im = im.crop(a.getbbox())
    k = box / max(im.size); return im.resize((max(1,round(im.width*k)), max(1,round(im.height*k))), Image.LANCZOS)
def card(icon, bg, label=None, badge=None):
    c = Image.new("RGBA", (512,512), bg+(255,)); d = ImageDraw.Draw(c)
    # studs like the game's buttons
    for y in range(16, 512, 48):
        for x in range(16, 512, 48):
            d.ellipse([x, y, x+20, y+20], fill=tuple(min(255, v+22) for v in bg)+(255,))
    glow = Image.new("RGBA", (512,512), (0,0,0,0)); gd = ImageDraw.Draw(glow)
    for r in range(230, 0, -10):
        gd.ellipse([256-r,256-r,256+r,256+r], fill=(255,255,255,int(70*(1-r/230))))
    c.alpha_composite(glow)
    ic = fit(icon, 400); c.alpha_composite(ic, ((512-ic.width)//2, (512-ic.height)//2))
    if badge is not None:
        b = fit(badge, 190); c.alpha_composite(b, (512-b.width-14, 512-b.height-14))
    if label:
        f = ImageFont.truetype(FONT, 120 if len(label) <= 3 else 92)
        d = ImageDraw.Draw(c); w = d.textlength(label, font=f)
        x = 24 if badge is not None else 512-w-24
        d.text((x, 512-150), label, font=f, fill=(255,255,255), stroke_width=12, stroke_fill=(20,20,28))
    d = ImageDraw.Draw(c); d.rectangle([0,0,511,511], outline=(20,20,28), width=14)
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
        ic, lab = PASS[key]; img = card(load(ic), C["pass_"], lab); plan[key] = (pid, name, "pass")
        img.save(f"out/{key}.png"); continue
    if kind == "EggPack":
        r = re.search(r'Rarity = "(\w+)"', rest)[1]; img = card(tint(egg, RAR[r]), BGR[r], xl)
    elif kind == "LimitedEgg":
        img = card(tint(egg, RAR["Halloween"]), BGR["Halloween"], xl)
    elif kind == "SkipHatch":
        r = key.replace("SkipHatch", ""); img = card(tint(egg, RAR[r]), BGR[r], None, timer)
    elif kind == "ItemPack":
        img = card(load(ITEM[re.search(r'Item = "(\w+)"', rest)[1]]), C["item"], xl)
    elif kind == "ToolSkip":
        t = TOOLS[re.search(r'Tier = (\d+)', rest)[1]]; img = card(load(f"Icon_Tool_{t}"), C["tool"])
    elif kind in ("VehicleUnlock", "VehicleRental"):
        car = key.replace("Unlock", "").replace("Rent", "")
        img = card(load(f"Icon_Car_{car}"), C["car"], None, timer if kind == "VehicleRental" else None)
    elif kind == "GiftPass":
        p = key.replace("Gift", ""); ic, lab = PASS[p]; img = card(load(ic), C["gift"], lab, gift)
    elif kind == "StarterPack":
        img = card(gift, (220,120,20), None, load("Icon_Star"))
    elif kind == "ServerLuck":
        mult = re.search(r'Mult = (\d+)', rest)[1]; img = card(load("Icon_Luck"), C["boost"], mult + "x")
    elif kind == "MeteorShower":
        img = card(load("Icon_Meteor"), C["boost"])
    elif kind == "CashPack":
        img = card(load("Icon_Cash"), C["cash"])
    elif kind == "SkipRebirth":
        img = card(load("Icon_Rebirth"), C["rebirth"])
    elif kind == "WheelSpins":
        img = card(load("Icon_Spin"), C["spin"], xl)
    elif kind == "MerchantRestock":
        img = card(load("Icon_Merchant"), C["item"])
    elif kind == "DoubleOffline":
        img = card(timer, C["boost"], "2x")
    else:
        print("skip", key, kind); continue
    img.save(f"out/{key}.png"); plan[key] = (pid, name, "product")
json.dump(plan, open("plan2.json", "w"), indent=1); print(len(plan))
# preview sheet
ks = list(plan); cols = 12; S = 120
sheet = Image.new("RGB", (cols*S, ((len(ks)+cols-1)//cols)*S), (30,30,40))
for i, k in enumerate(ks):
    sheet.paste(Image.open(f"out/{k}.png").convert("RGB").resize((S-6, S-6)), ((i%cols)*S+3, (i//cols)*S+3))
sheet.save("sheet2.png")
