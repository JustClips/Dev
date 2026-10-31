"""Builds the upgrade tree hexes in src/shared/Config/Upgrades.luau (between the
GENERATED TREE markers) from the spec below.

Slime RNG style (Dev, 2026-10-31): every upgrade step is its own hex that you buy once,
and a step's next one sits next to it, so the tree grows outwards as you buy. Each spec
row becomes a chain of up to 3 hexes (its levels split over them, each hex costing what
those levels cost). Children hang off the first hex of their parent's chain. Hex names say
what they give ("+50% Leaves", "+1 Egg Slot").

  python3 tools/gen_upgrade_tree.py            # rewrite the tree in Upgrades.luau
  python3 tools/gen_upgrade_tree.py --preview  # also draw art/out/tree_<Board>.png

Lab boards keep their centre {0,0} free: the window draws the lab's red Back hex there.
"""
import math
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LUA = os.path.join(ROOT, "src", "shared", "Config", "Upgrades.luau")
MAX_CHAIN = 3

# (board, id, parent, stat, description, levels, bonus per level, first price, price growth, rebirths, icon)
# A "Portal:<board>:<name>" stat is a lab hex that opens that board.
SPEC = [
    ('Main', 'Power', None, 'Power', 'Every pile gives more leaves', 5, 0.25, 150, 1.9, 0, None),
    ('Main', 'Backpack', 'Power', 'Backpack', 'Carry more leaves per trip', 5, 0.3, 300, 2.2, 0, None),
    ('Main', 'Speed', 'Power', 'Speed', 'Walk faster', 5, 2.0, 400, 2.0, 0, None),
    ('Main', 'LeafValue', 'Power', 'DustValue', 'Every leaf sells for more', 5, 0.15, 800, 2.2, 0, None),
    ('Main', 'PetLab', 'Power', 'Portal:Pets:Pet Lab', 'Pet income, pet fights and offline cash', 1, 0, 1500, 1, 0, 'Icon_Alien'),
    ('Main', 'WorkGloves', 'Backpack', 'Power', 'Grab more leaves from every pile', 5, 0.25, 3000, 2.0, 0, 'Icon_UpGloves'),
    ('Main', 'QuickDump', 'Backpack', 'DumpSpeed', 'Your bag pours into the dump faster', 5, 0.2, 5000, 8.1, 0, None),
    ('Main', 'EggLab', 'WorkGloves', 'Portal:Eggs:Egg Lab', 'Egg luck, Huge pets, mutations and hatching', 1, 0, 2000, 1, 0, 'Icon_Egg'),
    ('Main', 'LuckyLab', 'QuickDump', 'Portal:Lucky:Lucky Lab', 'Lucky sweeps, golden piles and bunnies', 1, 0, 5000, 1, 0, 'Icon_Star'),
    ('Main', 'BigPockets', 'Backpack', 'Backpack', 'Even more room in your bag', 5, 0.3, 8000, 4.9, 0, 'Icon_UpSack'),
    ('Main', 'GiantSack', 'BigPockets', 'Backpack', 'Carry a huge sack of leaves', 5, 0.4, 150000, 5.3, 0, 'Icon_UpSack'),
    ('Main', 'LeafTruck', 'BigPockets', 'Backpack', 'Carry way more leaves', 5, 0.4, 3000000000, 4.9, 1, 'Icon_Car_DustTruck'),
    ('Main', 'LeafTrailer', 'GiantSack', 'Backpack', 'Hook a whole trailer of leaves to your bag', 5, 0.2, 60000000000, 4.9, 2, 'Icon_Car_DustTruck'),
    ('Main', 'WideSweep', 'WorkGloves', 'Radius', 'Sweep a bigger area at once', 5, 0.05, 25000, 6.1, 0, None),
    ('Main', 'IronGrip', 'WorkGloves', 'Power', 'Tough piles break in fewer swipes', 5, 0.3, 40000, 5.7, 0, 'Icon_UpGloves'),
    ('Main', 'MegaSweep', 'WideSweep', 'Radius', 'Sweep an even bigger area', 5, 0.05, 3000000000, 6.1, 1, None),
    ('Main', 'Tornado', 'MegaSweep', 'Radius', 'Sweep a huge area at once', 5, 0.06, 200000000000, 7.1, 3, 'Icon_Tool_TornadoVac'),
    ('Main', 'MuscleUp', 'IronGrip', 'Power', 'Much more leaves from every pile', 5, 0.4, 2000000000, 4.9, 1, 'Icon_UpDumbbell'),
    ('Main', 'TitanStrength', 'IronGrip', 'Power', 'Huge leaf hauls from every pile', 5, 0.6, 30000000000, 4.9, 2, 'Icon_UpDumbbell'),
    ('Main', 'LuckyFinds', 'Speed', 'ItemFind', 'Items drop from the leaves more often', 5, 0.05, 3000, 2.8, 0, 'Icon_UpMagnifier'),
    ('Main', 'LongBrew', 'Speed', 'PotionTime', 'Potions last longer', 5, 0.1, 8000, 8.1, 0, 'Icon_Potion'),
    ('Main', 'SpringShoes', 'QuickDump', 'Speed', 'Bounce along even faster', 3, 2.0, 200000, 5.7, 0, 'Icon_Speed'),
    ('Main', 'TreasureHunter', 'LuckyFinds', 'ItemFind', 'Items drop from the leaves way more often', 5, 0.05, 4000000000, 7.1, 1, 'Icon_TreasureMap'),
    ('Main', 'RocketShoes', 'LuckyFinds', 'Speed', 'Zoom around with rocket power', 5, 2.0, 3000000000, 5.7, 1, None),
    ('Main', 'MoneyMagnet', 'LeafValue', 'Cash', 'Grab coins from further away, plus more cash', 5, 0.1, 50000, 5.7, 0, 'Icon_UpMagnet'),
    ('Main', 'FancyLeaves', 'LeafValue', 'DustValue', 'Every leaf sells for even more', 5, 0.3, 60000, 5.3, 0, 'Icon_UpGem'),
    ('Main', 'Haggler', 'MoneyMagnet', 'MerchantDiscount', 'The Traveling Merchant gives you a discount', 4, 0.05, 100000, 8.1, 0, None),
    ('Main', 'BiggerCart', 'Haggler', 'MerchantSlots', 'The Traveling Merchant shows one more item', 2, 1.0, 5000000000, 20.0, 1, None),
    ('Main', 'RichSweeper', 'MoneyMagnet', 'Cash', 'Bigger coin magnet, plus more cash', 5, 0.1, 5000000000, 5.7, 1, 'Icon_UpMagnet'),
    ('Main', 'GoldenBroom', 'RichSweeper', 'Cash', 'Huge coin magnet, plus more cash', 5, 0.1, 250000000000, 5.7, 3, 'Icon_Tool_GoldenBroom'),
    ('Main', 'Fertilizer', 'FancyLeaves', 'Regrow', 'Your leaves grow back faster', 4, 0.03, 3000000000, 8.1, 1, 'Icon_UpSprout'),
    ('Main', 'DiamondLeaves', 'FancyLeaves', 'DustValue', 'Every leaf sells for way more', 5, 0.45, 45000000000, 5.3, 2, 'Icon_UpGem'),
    ('Eggs', 'Luck', None, 'Luck', 'Find more and rarer eggs', 5, 0.1, 1000, 2.5, 0, None),
    ('Eggs', 'HatchSpeed', 'Luck', 'HatchSpeed', 'Eggs grow faster', 5, 0.1, 30000, 6.6, 0, None),
    ('Eggs', 'EggSniffer', 'Luck', 'EggFind', 'Find eggs in the leaves more often', 5, 0.05, 15000, 7.1, 0, 'Icon_UpMagnifier'),
    ('Eggs', 'HugeHunter', 'Luck', 'Huge', 'Pets hatch Huge more often', 5, 0.2, 50000, 8.1, 0, None),
    ('Eggs', 'Incubator', 'Luck', 'Incubators', 'Grow one more egg at once', 1, 1.0, 150000, 1.0, 0, 'Icon_UpNest'),
    ('Eggs', 'LuckyCharm', 'Luck', 'Luck', 'Find even rarer eggs', 5, 0.1, 400000, 5.7, 0, 'Icon_LuckyClover'),
    ('Eggs', 'StormChaser', 'Luck', 'WeatherMut', 'Weather mutates your growing eggs more often', 5, 0.2, 80000, 7.1, 0, 'Icon_Weather_Thunderstorm'),
    ('Eggs', 'HatchHurry', 'HatchSpeed', 'HatchSpeed', 'Eggs grow even faster', 5, 0.1, 5000000000, 6.6, 1, 'Icon_PotionHatch'),
    ('Eggs', 'ShinyHunter', 'HugeHunter', 'MutChance', 'Golden, Rainbow and Sparkly pets more often', 5, 0.2, 3000000000, 7.1, 1, None),
    ('Eggs', 'HugeMagnet', 'HugeHunter', 'Huge', 'Pets hatch Huge way more often', 5, 0.2, 8000000000, 7.1, 2, 'Icon_HugeCharm'),
    ('Eggs', 'EggRadar', 'EggSniffer', 'EggFind', 'Find eggs in the leaves way more often', 5, 0.05, 4000000000, 7.1, 1, 'Icon_UpMagnifier'),
    ('Eggs', 'EggNursery', 'Incubator', 'Incubators', 'Grow another egg at once', 1, 1.0, 25000000000, 1.0, 1, 'Icon_UpNest'),
    ('Eggs', 'FourLeaf', 'LuckyCharm', 'Luck', 'Find way rarer eggs', 5, 0.1, 2500000000, 6.1, 1, 'Icon_LuckyClover'),
    ('Eggs', 'RainbowLuck', 'LuckyCharm', 'Luck', 'Rainbow-level egg luck', 5, 0.1, 6000000000, 7.1, 2, 'Icon_Weather_Rainbow'),
    ('Eggs', 'Horseshoe', 'FourLeaf', 'Luck', 'The best egg luck there is', 5, 0.1, 250000000000, 8.1, 3, 'Icon_UpHorseshoe'),
    ('Lucky', 'Golden', None, 'Golden', 'Golden piles pay more', 5, 0.2, 40000, 7.1, 0, None),
    ('Lucky', 'Crit', 'Golden', 'Crit', 'Chance a leaf pays 5x', 5, 0.01, 50000, 7.1, 0, None),
    ('Lucky', 'Bunny', 'Golden', 'Bunny', 'Dust bunnies drop more cash', 5, 0.25, 20000, 5.7, 0, None),
    ('Lucky', 'LuckyPaw', 'Golden', 'Crit', 'A few more lucky leaves', 3, 0.01, 600000, 7.1, 0, 'Icon_LuckyCat'),
    ('Lucky', 'GoldDigger', 'Golden', 'Golden', 'Golden piles pay a bit more', 3, 0.15, 500000, 6.1, 0, 'Icon_UpGem'),
    ('Lucky', 'BunnyNet', 'Bunny', 'BunnyReach', 'Catch dust bunnies from further away', 4, 0.25, 60000, 7.1, 0, None),
    ('Lucky', 'GoldRush', 'Golden', 'Golden', 'Golden piles pay even more', 5, 0.25, 4000000000, 6.6, 1, None),
    ('Lucky', 'LuckyStreak', 'Crit', 'Crit', 'Even more lucky leaves', 5, 0.01, 4000000000, 7.1, 1, None),
    ('Lucky', 'Jackpot', 'Crit', 'CritMult', 'Lucky sweeps pay more', 5, 1.0, 5000000000, 6.6, 1, 'Icon_Cash'),
    ('Lucky', 'BunnyBoss', 'Bunny', 'Bunny', 'Dust bunnies drop way more cash', 5, 0.5, 2000000000, 5.7, 1, None),
    ('Lucky', 'Midas', 'GoldRush', 'Golden', 'Golden piles pay way more', 5, 0.5, 45000000000, 7.1, 2, None),
    ('Lucky', 'MegaJackpot', 'Jackpot', 'CritMult', 'Lucky sweeps pay way more', 3, 2.0, 150000000000, 8.1, 3, 'Icon_Cash'),
    ('Pets', 'PetIncome', None, 'PetIncome', 'Pets in your park earn more', 5, 0.2, 1500, 2.3, 0, 'Icon_UpHeart'),
    ('Pets', 'PetTreats', 'PetIncome', 'PetIncome', 'Pets in your park earn even more', 5, 0.3, 30000, 5.3, 0, 'Icon_UpBone'),
    ('Pets', 'Offline', 'PetIncome', 'Offline', "Earn more while you're away", 5, 0.2, 25000, 5.7, 0, 'Icon_UpMoon'),
    ('Pets', 'GoodDeals', 'PetIncome', 'PetSell', 'The Pet Trader pays more for your pets', 5, 0.15, 10000, 6.1, 0, None),
    ('Pets', 'SharpClaws', 'PetIncome', 'PetDamage', 'Your pets hit harder', 5, 0.2, 8000, 5.7, 0, 'Icon_Sword'),
    ('Pets', 'ThickFur', 'PetIncome', 'PetHealth', 'Your pets can take more hits', 5, 0.2, 8000, 5.7, 0, 'Icon_UpShield'),
    ('Pets', 'BestFriends', 'PetTreats', 'PassivePower', "Your pets' passive powers get stronger", 5, 0.06, 500000, 7.1, 0, 'Icon_UpHeart'),
    ('Pets', 'PetParty', 'PetTreats', 'PetIncome', 'Pets in your park earn a lot more', 5, 0.4, 4000000000, 5.3, 1, 'Icon_UpBone'),
    ('Pets', 'PetParadise', 'PetParty', 'PetIncome', 'Pets in your park earn way more', 5, 0.5, 60000000000, 5.3, 2, 'Icon_UpHeart'),
    ('Pets', 'SleepPay', 'Offline', 'Offline', "Earn even more while you're away", 5, 0.25, 3000000000, 5.7, 1, 'Icon_UpMoon'),
    ('Pets', 'LongNap', 'Offline', 'OfflineCap', 'Earn offline for longer', 4, 0.5, 2000000000, 5.7, 1, 'Icon_UpMoon'),
    ('Pets', 'BattleTraining', 'SharpClaws', 'PetDamage', 'Your pets hit way harder', 5, 0.3, 3000000000, 5.7, 1, 'Icon_Sword'),
    ('Pets', 'PetArmor', 'ThickFur', 'PetHealth', 'Your pets can take way more hits', 5, 0.3, 3000000000, 5.7, 1, 'Icon_UpShield'),
]

# Hex names: one name per stat, numbered I, II, III... from cheapest to dearest (Dev,
# 2026-10-31: "Big Bag I, Big Bag II"). The exact numbers are in the tooltip.
FAMILY = {
    "Power": "Sweep Power", "Backpack": "Big Bag", "Speed": "Fast Feet", "DustValue": "Leaf Value", "Radius": "Wide Sweep",
    "Cash": "Coin Magnet", "DumpSpeed": "Quick Dump", "ItemFind": "Lucky Finds", "PotionTime": "Long Potions",
    "MerchantDiscount": "Merchant Deal", "MerchantSlots": "Merchant Cart", "Regrow": "Fast Regrow", "Luck": "Egg Luck",
    "HatchSpeed": "Quick Hatch", "EggFind": "Egg Finder", "Huge": "Huge Hunter", "Incubators": "Egg Slot",
    "WeatherMut": "Storm Eggs", "MutChance": "Shiny Pets", "Golden": "Golden Piles", "Crit": "Lucky Leaves",
    "CritMult": "Jackpot", "Bunny": "Bunny Cash", "BunnyReach": "Bunny Net", "PetIncome": "Pet Income",
    "Offline": "Offline Cash", "OfflineCap": "Long Nap", "PetSell": "Pet Trader", "PetDamage": "Pet Power",
    "PetHealth": "Pet Armor", "PassivePower": "Pet Passives",
}


def roman(n):
    out = ""
    for v, sym in ((10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")):
        while n >= v:
            out += sym
            n -= v
    return out


def name_hexes(hexes):
    by_stat = {}
    for h in hexes:
        if not h["lab"]:
            by_stat.setdefault(h["stat"], []).append(h)
    for stat, hs in by_stat.items():
        hs.sort(key=lambda h: (h["rb"], h["cost"]))
        for i, h in enumerate(hs):
            h["name"] = f"{FAMILY[stat]} {roman(i + 1)}" if len(hs) > 1 else FAMILY[stat]


# Short stat words (old names, kept for reference).
LABEL = {
    "Power": "Leaves", "Backpack": "Bag Space", "Speed": "Speed", "DustValue": "Leaf Price", "Radius": "Sweep Size",
    "Cash": "Cash + Magnet", "DumpSpeed": "Dump Speed", "ItemFind": "Item Drops", "PotionTime": "Potion Time",
    "MerchantDiscount": "Merchant Sale", "MerchantSlots": "Merchant Item", "Regrow": "Regrow Speed", "Luck": "Egg Luck",
    "HatchSpeed": "Hatch Speed", "EggFind": "Eggs Found", "Huge": "Huge Chance", "Incubators": "Egg Slot",
    "WeatherMut": "Weather Mutation", "MutChance": "Mutation Chance", "Golden": "Golden Pile Cash", "Crit": "Lucky Leaves",
    "CritMult": "Lucky Payout", "Bunny": "Bunny Cash", "BunnyReach": "Bunny Range", "PetIncome": "Pet Income",
    "Offline": "Offline Cash", "OfflineCap": "Offline Time", "PetSell": "Pet Sell Price", "PetDamage": "Pet Damage",
    "PetHealth": "Pet Health", "PassivePower": "Pet Passives",
}
FORMAT = {"Speed": "plus", "Incubators": "plus", "MerchantSlots": "plus", "CritMult": "x", "OfflineCap": "hours"}

DIRS = [(0, -1), (1, -1), (1, 0), (0, 1), (-1, 1), (-1, 0)]


def value_text(stat, b):
    f = FORMAT.get(stat, "percent")
    if f == "percent":
        pct = b * 100
        return f"+{round(pct, 1):g}%"
    if f == "x":
        return f"+{b:g}x"
    if f == "hours":
        return f"+{b:g}h"
    return f"+{b:g}"


def pixel(q, r):
    return 1.5 * q, math.sqrt(3) * (r + q / 2)


def dist(q, r):
    return max(abs(q), abs(r), abs(q + r))


def groups(levels):
    n = min(levels, MAX_CHAIN)
    sizes = [levels // n + (1 if i < levels % n else 0) for i in range(n)]
    out, first = [], 0
    for s in sizes:
        out.append((first, s))
        first += s
    return out


def build():
    hexes = []  # dicts
    taken = {}
    chains = {}
    for board, nid, parent, stat, desc, levels, per, base, growth, rb, icon in SPEC:
        occ = taken.setdefault(board, {(0, 0)} if board != "Main" else set())

        def free_near(cells, heading):
            best = None
            for ci, (cq, cr) in enumerate(cells):
                for dq, dr in DIRS:
                    q, r = cq + dq, cr + dr
                    if (q, r) in occ:
                        continue
                    px, py = pixel(q, r)
                    hx, hy = heading
                    score = (-ci, dist(q, r), px * hx + py * hy)
                    if best is None or score > best[0]:
                        best = (score, (q, r), (cq, cr))
                if best:
                    return best[1], best[2]
            return None, None

        if parent is None:
            cell, par_cell, par_id = ((0, 0) if board == "Main" else (0, -1)), None, None
        else:
            pchain = chains[parent]
            cells = [h["cell"] for h in pchain]
            hx, hy = pixel(*cells[0])
            cell, par_cell = free_near(cells, (hx, hy) if (hx, hy) != (0, 0) else (0, -1))
            assert cell, f"no room for {nid}"
            par_id = next(h["id"] for h in pchain if h["cell"] == par_cell)
        chain = []
        if stat.startswith("Portal:"):
            _, opens, name = stat.split(":")
            h = dict(id=nid, board=board, cell=cell, parent=par_id, lab=True, opens=opens, name=name, desc=desc,
                     cost=base, icon=icon, rb=0)
            occ.add(cell)
            hexes.append(h)
            chains[nid] = [h]
            continue
        for k, (first, size) in enumerate(groups(levels)):
            if k > 0:
                prev = chain[-1]["cell"]
                before = chain[-2]["cell"] if len(chain) > 1 else (par_cell or (0, 0))
                px, py = pixel(*prev)
                bx, by = pixel(*before)
                cell, _ = free_near([prev], (px - bx, py - by))
                if cell is None:
                    cell, pc = free_near([c["cell"] for c in chain], (px, py))
                    assert cell, f"no room for {nid} step {k + 1}"
                    par_id = next(c["id"] for c in chain if c["cell"] == pc)
                else:
                    par_id = chain[-1]["id"]
            cost = sum(math.floor(base * growth ** i) for i in range(first, first + size))
            # Keep prices readable: 3 significant digits.
            mag = 10 ** max(0, len(str(cost)) - 3)
            cost = int(round(cost / mag) * mag)
            bonus = round(per * size, 4)
            h = dict(id=nid if k == 0 else f"{nid}_{k + 1}", board=board, cell=cell, parent=par_id, lab=False, stat=stat,
                     name=f"{value_text(stat, bonus)} {LABEL[stat]}", desc=desc, bonus=bonus, cost=cost, rb=rb, icon=icon)
            occ.add(cell)
            hexes.append(h)
            chain.append(h)
        chains[nid] = chain
    return hexes


def lua_num(n):
    return f"{n:_}" if isinstance(n, int) else f"{n:g}"


def write(hexes):
    out = []
    icons = {}
    for board in ("Main", "Eggs", "Lucky", "Pets"):
        var = {"Main": "Main", "Eggs": "Eggs", "Lucky": "Lucky", "Pets": "Pets"}[board]
        out.append("-- stylua: ignore")
        out.append(f"local {var} = {{" if board == "Main" else f'local {var} = inTree("{board}", {{')
        for h in (h for h in hexes if h["board"] == board):
            q, r = h["cell"]
            par = f'"{h["parent"]}"' if h["parent"] else "nil"
            if h["lab"]:
                out.append(f'\tlab("{h["id"]}", {q}, {r}, {par}, "{h["opens"]}", "{h["name"]}", "{h["desc"]}", "{h["icon"]}", {lua_num(h["cost"])}),')
                continue
            rb = f", {h['rb']}" if h["rb"] else ""
            out.append(f'\tn("{h["id"]}", {q}, {r}, {par}, "{h["stat"]}", "{h["name"]}", "{h["desc"]}", 1, {lua_num(h["bonus"])}, {lua_num(h["cost"])}, 1{rb}),')
            if h["icon"]:
                icons[h["id"]] = h["icon"]
        out.append("}" if board == "Main" else "})")
        out.append("")
    out.append("-- Hex pictures: the stat's icon unless a hex has its own here (hand-drawn sticker icons,")
    out.append("-- art/flat_icons.py). A name that isn't uploaded yet falls back to the stat's icon.")
    out.append("-- stylua: ignore")
    out.append("local Icons: { [string]: string } = {")
    for k, v in icons.items():
        out.append(f'\t["{k}"] = "{v}",')
    out.append("}")
    src = open(LUA).read()
    a = src.index("-- BEGIN GENERATED TREE")
    b = src.index("-- END GENERATED TREE")
    head = "-- BEGIN GENERATED TREE (tools/gen_upgrade_tree.py; edit the spec there, not here)\n"
    open(LUA, "w").write(src[:a] + head + "\n".join(out) + "\n" + src[b:])


def preview(hexes):
    from PIL import Image, ImageDraw, ImageFont
    font = os.path.join(ROOT, "art", "blender", "fonts", "Montserrat-Black.ttf")
    F, FS = ImageFont.truetype(font, 15), ImageFont.truetype(font, 14)
    S = 60
    for board in ("Main", "Eggs", "Lucky", "Pets"):
        hs = [h for h in hexes if h["board"] == board]
        pts = [(S * pixel(*h["cell"])[0], S * pixel(*h["cell"])[1]) for h in hs] + [(0, 0)]
        minx, maxx = min(p[0] for p in pts) - 70, max(p[0] for p in pts) + 70
        miny, maxy = min(p[1] for p in pts) - 60, max(p[1] for p in pts) + 60
        im = Image.new("RGBA", (int(maxx - minx), int(maxy - miny)), (46, 90, 52, 255))
        d = ImageDraw.Draw(im)
        def hexagon(cx, cy, R, fill):
            d.polygon([(cx + R * math.cos(math.radians(60 * i)), cy + R * math.sin(math.radians(60 * i))) for i in range(6)], fill=fill)
        if board != "Main":
            hexagon(-minx, -miny, S - 2, (23, 25, 30)); hexagon(-minx, -miny, S - 8, (235, 30, 45))
            d.text((-minx, -miny), "Back", font=F, anchor="mm", fill="white")
        for h, (x, y) in zip(hs, pts):
            cx, cy = x - minx, y - miny
            col = (61, 200, 90) if h["lab"] else ((91, 74, 143) if h["rb"] else (42, 49, 66))
            hexagon(cx, cy, S - 2, (23, 25, 30)); hexagon(cx, cy, S - 8, col)
            icon = h.get("icon") or ""
            path = os.path.join(ROOT, "art", "out", "icons", icon[5:] + ".png")
            if icon and os.path.exists(path):
                ii = Image.open(path).convert("RGBA").resize((34, 34)); im.alpha_composite(ii, (int(cx - 17), int(cy - 46)))
            words = h["name"].split(" ", 1)
            d.text((cx, cy - 2), words[0], font=F, anchor="mm", fill="white", stroke_width=2, stroke_fill=(20, 20, 20))
            d.text((cx, cy + 15), words[1] if len(words) > 1 else "", font=FS, anchor="mm", fill="white", stroke_width=2, stroke_fill=(20, 20, 20))
            price = f"R{h['rb']}" if h["rb"] else f"${h['cost']:,}"
            d.text((cx, cy + 33), price, font=FS, anchor="mm", fill=(255, 220, 120), stroke_width=2, stroke_fill=(20, 20, 20))
        os.makedirs(os.path.join(ROOT, "art", "out"), exist_ok=True)
        im.save(os.path.join(ROOT, "art", "out", f"tree_{board}.png"))


if __name__ == "__main__":
    hx = build()
    name_hexes(hx)
    write(hx)
    if "--preview" in sys.argv:
        preview(hx)
    print(len(hx), "hexes:", {b: sum(1 for h in hx if h["board"] == b) for b in ("Main", "Eggs", "Lucky", "Pets")})
