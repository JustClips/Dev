"""Progression model for Sweep the World.

Reads the real numbers from src/shared/Config/*.luau (so it never drifts from the game) and
plays a simulated kid through the game: sweep, sell, find eggs, carry them home, hatch,
place the best pets, buy tools / cars / zones / upgrade-tree levels, rebirth.

It runs three spenders side by side so we can see how pay-to-win the game is:
  free   - never pays. Gets daily rewards, playtime gifts and offline income.
  light  - Starter Pack + 2x Cash + Sell Anywhere (about 300 R$, the usual first buys).
  whale  - every gamepass, Skip Rebirth once a day (needs 30% saved), 3 Cosmic eggs, cash packs,
           a car unlock and server luck now and then (thousands of R$).

Play is in 1.5 h sessions, one per day (offline income in between).

    python3 tools/balance/sim.py            # milestone table, 12 seeds each
    python3 tools/balance/sim.py --hours 60 --seeds 20
"""

from __future__ import annotations

import argparse
import math
import random
import re
import statistics
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CFG = ROOT / "src" / "shared" / "Config"

# ---------------------------------------------------------------- behaviour knobs
WALK = 16  # studs/s
TICKS = 10  # sweep ticks per second
SELL_TRIP = 10.0  # seconds lost per sell (teleport to the dumps, pour, teleport back)
SELL_TRIP_PASS = 1.5  # Sell Anywhere: one tap
COMBO = 1.6  # average combo multiplier while sweeping (x1..x3)
GOLDEN = 1.12  # golden piles and dust bunnies on top
EFFICIENCY = 0.5  # kids on phones wander, chat, open menus (tuned for mobile, PC players go faster)
FIELD_SHARE = 0.5  # share of a zone's regrowth one player gets (others sweep too)
SESSION_HOURS = 1.5  # one session a day
STEP = 2.0  # sim step, seconds
WEATHER_GROW = 1.12  # average egg growth bonus from rain / storms
WEIGHT_MULT = 1.22  # average pet weight multiplier (Config/Weights size classes)


# ---------------------------------------------------------------- tiny Luau readers
def _num(s: str) -> float:
    return float(s.replace("_", ""))


def _blocks(text: str):
    """Yield every {...} block (balanced) that has an Id at its top level."""
    depth, start = 0, []
    for i, ch in enumerate(text):
        if ch == "{":
            start.append(i)
            depth += 1
        elif ch == "}":
            depth -= 1
            s = start.pop()
            body = text[s + 1 : i]
            yield body


def _top_pairs(body: str) -> dict:
    """Key = number / "string" / true pairs at depth 0 of a block body."""
    out, depth, flat = {}, 0, []
    for ch in body:
        if ch in "{(":
            depth += 1
        elif ch in "})":
            depth -= 1
        elif depth == 0:
            flat.append(ch)
            continue
        flat.append(" ")
    flat = "".join(flat)
    for k, v in re.findall(r"(\w+)\s*=\s*(\"[^\"]*\"|-?[\d_.]+(?:\s*/\s*[\d_.]+)?|true|false)", flat):
        if "/" in v:
            num, den = v.split("/")
            out[k] = _num(num.strip()) / _num(den.strip())
        elif v.startswith('"'):
            out[k] = v[1:-1]
        elif v in ("true", "false"):
            out[k] = v == "true"
        else:
            out[k] = _num(v)
    return out


def _entries(path: str, must: str = "Id") -> list[dict]:
    text = (CFG / path).read_text()
    text = re.sub(r"--[^\n]*", "", text)
    rows = []
    for body in _blocks(text):
        pairs = _top_pairs(body)
        if must in pairs:
            m = re.search(r"Passive\s*=\s*\{([^}]*)\}", body)
            if m:
                pairs["Passive"] = _top_pairs(m.group(1))
            rows.append(pairs)
    return rows


def _economy() -> dict:
    text = re.sub(r"--[^\n]*", "", (CFG / "Economy.luau").read_text())
    body = text[text.index("{") + 1 : text.rindex("}")]
    eco = _top_pairs(body)
    m = re.search(r"SlotCashPrices\s*=\s*\{([^}]*)\}", body)
    eco["SlotCashPrices"] = [_num(x) for x in re.findall(r"[\d_]+", m.group(1))]
    m = re.search(r"RebirthCosts\s*=\s*\{([^}]*)\}", body)
    eco["RebirthCosts"] = [_num(x) for x in re.findall(r"[\d_.]+(?:e\d+)?", m.group(1))]
    for sub in ("Combo", "Golden", "Bunnies"):
        m = re.search(sub + r"\s*=\s*\{([^}]*)\}", body)
        eco[sub] = _top_pairs(m.group(1))
    return eco


def _upgrades() -> list[dict]:
    text = re.sub(r"--[^\n]*", "", (CFG / "Upgrades.luau").read_text())
    rows = []
    tree = "Main"
    for line in text.splitlines():
        t = re.match(r"local (\w+) = inTree\(\"(\w+)\"", line.strip())
        if t:
            tree = t.group(2)
        m = re.search(
            r"\bn\(\"(\w+)\",\s*(-?\d+),\s*(-?\d+),\s*(nil|\"\w+\"),\s*\"(\w+)\",\s*\"[^\"]*\",\s*\"[^\"]*\","
            r"\s*([\d.]+),\s*([\d.]+),\s*([\d_]+),\s*([\d.]+)(?:,\s*(\d+))?\)",
            line,
        )
        if m:
            rows.append(
                dict(
                    Id=m.group(1),
                    Tree=tree,
                    Parent=None if m.group(4) == "nil" else m.group(4).strip('"'),
                    Stat=m.group(5),
                    MaxLevel=int(m.group(6)),
                    PerLevel=float(m.group(7)),
                    BaseCost=_num(m.group(8)),
                    CostGrowth=float(m.group(9)),
                    RequiredRebirths=int(m.group(10) or 0),
                )
            )
        m = re.search(r"\blab\(\"(\w+)\",\s*-?\d+,\s*-?\d+,\s*\"(\w+)\",.*?([\d_]+)\),\s*$", line)
        if m:
            rows.append(
                dict(Id=m.group(1), Tree="Main", Parent="Power", Stat="Portal", MaxLevel=1, PerLevel=0,
                     BaseCost=_num(m.group(3)), CostGrowth=1, RequiredRebirths=0, Opens=m.group(2))
            )
    return rows


def _rarities():
    rows = _entries("Eggs.luau", "Order")
    rar = [r for r in rows if "HatchSeconds" in r]
    muts = [r for r in _entries("Eggs.luau", "Chance") if r.get("Chance", 0) > 0 and not r.get("WeatherOnly")]
    text = (CFG / "Eggs.luau").read_text()
    fh = float(re.search(r"FasterHatchMult\s*=\s*([\d.]+)", text).group(1))
    odds = {}
    for key in ("Up", "Down"):
        m = re.search(key + r"\s*=\s*\{([^}]*)\}", text)
        odds[key] = [float(x) for x in re.findall(r"[\d.]+", m.group(1))] if m else []
    m = re.search(r"UpCap\s*=\s*([\d.]+)", text)
    odds["UpCap"] = float(m.group(1)) if m else 100.0
    return rar, muts, fh, odds


def _products():
    rows = _entries("Products.luau", "Key")
    return {r["Key"]: r for r in rows}


def _aliens():
    rows = _entries("Aliens.luau")
    text = (CFG / "Aliens.luau").read_text()
    huge_chance = 1 / float(re.search(r"HugeChance\s*=\s*1\s*/\s*([\d_]+)", text).group(1).replace("_", ""))
    huge_mult = float(re.search(r"HugeIncomeMult\s*=\s*([\d.]+)", text).group(1))
    return [r for r in rows if "Income" in r], huge_chance, huge_mult


def _items():
    rows = _entries("Items.luau")
    return {r["Id"]: r for r in rows}


def _rewards():
    text = re.sub(r"--[^\n]*", "", (CFG / "Rewards.luau").read_text())

    def section(name):
        m = re.search(r"Rewards\." + name + r"\s*=\s*\{(.*?)\n\}", text, re.S)
        return m.group(1)

    daily = [_top_pairs(b) for b in re.findall(r"\{([^{}]*)\}", section("Daily"))]
    play = []
    for minutes, body in re.findall(r"Minutes\s*=\s*([\d.]+),\s*Reward\s*=\s*\{([^}]*)\}", section("Playtime")):
        play.append((float(minutes), _top_pairs(body)))
    return daily, play


class Config:
    def __init__(self):
        self.eco = _economy()
        tools = _entries("Tools.luau")
        self.tools = sorted([t for t in tools if "Tier" in t], key=lambda t: t["Tier"])
        self.cars = sorted([t for t in tools if "Order" in t], key=lambda t: t["Order"])
        self.zones = _entries("Zones.luau")
        self.upgrades = _upgrades()
        self.up_by_id = {u["Id"]: u for u in self.upgrades}
        self.trees = {u["Opens"]: u["Id"] for u in self.upgrades if u.get("Opens")}
        self.rarities, self.mutations, self.faster_hatch, self.hatch_odds = _rarities()
        self.rorder = {r["Name"]: r["Order"] for r in self.rarities}
        self.rhatch = {r["Name"]: r["HatchSeconds"] for r in self.rarities}
        self.aliens, self.huge_chance, self.huge_mult = _aliens()
        self.pools: dict = {}
        for a in self.aliens:
            self.pools.setdefault(a.get("Zone", "Landing"), {}).setdefault(a["Rarity"], []).append(a)
        self.products = _products()
        self.items = _items()
        self.daily, self.playtime = _rewards()
        # tiles per zone (bounds / tile size; the Landing field is World.Field)
        world = (CFG / "World.luau").read_text()
        fm = re.search(r"World\.Field = \{ Min = Vector2\.new\((-?\d+), (-?\d+)\), Max = Vector2\.new\((-?\d+), (-?\d+)\)", world)
        fx0, fz0, fx1, fz1 = map(float, fm.groups())
        ztext = (CFG / "Zones.luau").read_text()
        bounds = re.findall(r"Id = \"(\w+)\".*?(?:Min = (World\.Field\.Min)|Min = Vector2\.new\((-?\d+), (-?\d+)\)),\s*Max = (?:World\.Field\.Max|Vector2\.new\((-?\d+), (-?\d+)\))", ztext, re.S)
        for z in self.zones:
            for b in bounds:
                if b[0] == z["Id"]:
                    if b[1]:
                        w, h = fx1 - fx0, fz1 - fz0
                    else:
                        w, h = float(b[4]) - float(b[2]), float(b[5]) - float(b[3])
                    z["Tiles"] = w * h / z["TileSize"] ** 2


# ---------------------------------------------------------------- the player
@dataclass
class Spender:
    name: str
    passes: set = field(default_factory=set)
    starter: bool = False
    skip_rebirth_at: float | None = None  # buys Skip Rebirth once cash reaches this share of the cost
    cosmic_eggs: int = 0
    car_unlock: str | None = None
    server_luck: float = 1.0  # average server luck they buy during their sessions
    cash_packs_per_day: int = 0  # "Crate of Cash" style buys per day
    cash_pack: str = "Cash3"


SPENDERS = [
    Spender("free"),
    Spender("light", passes={"Cash2x", "SellAnywhere"}, starter=True),
    Spender(
        "whale",
        passes={"Cash2x", "AutoSweep", "ExtraSlots", "Carry3", "VIP", "FasterHatch", "SellAnywhere"},
        starter=True,
        skip_rebirth_at=0.3,
        cosmic_eggs=3,
        car_unlock="SweeperCart",
        server_luck=2.0,
        cash_packs_per_day=2,
    ),
]


class Player:
    def __init__(self, cfg: Config, sp: Spender, rng: random.Random):
        self.c, self.sp, self.rng = cfg, sp, rng
        self.t = 0.0  # play seconds
        self.cash = 0.0
        self.tier = 1
        self.cars: set = set()
        self.zones = {"Landing"}
        self.levels: dict = {}
        self.rebirths = 0
        self.cash_slots = 0
        self.pets: list = []  # placed: dicts {income, def}
        self.bag_pets: list = []
        self.found: list = []  # eggs found since the last trip home: (order, rarity, zone)
        self.queue: list = []  # eggs at home waiting for an incubator
        self.incubators: list = []  # (ends_at, rarity, zone)
        self.boosts: dict = {}  # name -> play-time expiry
        self.items: dict = {}
        self.since_trip = 0.0
        self.log: list = []
        self.robux = 0
        self.day = 0
        self.daily_i = 0
        self.session_t = 0.0
        self.play_claimed = 0
        self.spent_upgrades = 0.0
        self.passes = set(sp.passes)
        self._stats = None
        self._pas = {}
        if sp.starter:
            st = cfg.eco  # StarterPack lives in Economy but is a table: hardcode the real shape
            self.cash += 500
            self.boosts["Cash2x"] = 10 * 60
            self.queue.append((2, "Uncommon", "Landing"))
            self.robux += cfg.products["StarterPack"]["Price"]
        for p in self.passes:
            self.robux += {"Cash2x": 99, "AutoSweep": 149, "ExtraSlots": 199, "Carry3": 129, "VIP": 249,
                           "FasterHatch": 229, "SellAnywhere": 199}[p]
        self.paid_cosmic = sp.cosmic_eggs  # Robux eggs always hatch their own rarity
        if sp.cosmic_eggs:
            for _ in range(sp.cosmic_eggs):
                self.queue.append((7, "Cosmic", "Landing"))
            self.robux += cfg.products["CosmicEgg3"]["Price"] if sp.cosmic_eggs == 3 else 99 * sp.cosmic_eggs
        self.car_bought = False

    # ---------------------------------------------------------- stats
    def passive_bonus(self) -> dict:
        seen, out = set(), {}
        for p in self.pets:
            d = p["def"]
            pas = d.get("Passive")
            if not pas or d["Id"] in seen:
                continue
            seen.add(d["Id"])
            out[pas["Stat"]] = out.get(pas["Stat"], 0) + pas["Value"] * (2 if p.get("huge") else 1)
        return out

    def stat(self, s: str, passive: dict | None = None) -> float:
        cache = self._stats
        if cache is None:
            cache = {}
            for u in self.c.upgrades:
                lvl = self.levels.get(u["Id"], 0)
                if lvl:
                    cache[u["Stat"]] = cache.get(u["Stat"], 0) + u["PerLevel"] * min(lvl, u["MaxLevel"])
            self._stats = cache
        return cache.get(s, 0.0) + (passive.get(s, 0) if passive is not None else 0)

    def boost(self, name: str) -> bool:
        return self.boosts.get(name, 0) > self.t

    def cash_mult(self, temp=True) -> float:
        eco = self.c.eco
        m = (1 + self.rebirths * eco["RebirthCashBonus"]) * (1 + self.stat("Cash", self._pas))
        if "Cash2x" in self.passes:
            m *= eco["Cash2xPassMult"]
        if "VIP" in self.passes:
            m *= 1 + eco["VIPCashBonus"]
        if temp and self.boost("Cash2x"):
            m *= eco["Cash2xBoostMult"]
        return m

    def luck(self) -> float:
        l = (1 + self.stat("Luck", self._pas)) * self.sp.server_luck
        if self.boost("Luck2x"):
            l *= 2
        return l

    def slots(self) -> int:
        eco = self.c.eco
        n = eco["BaseSlots"] + self.rebirths // eco["RebirthsPerExtraSlot"] + min(self.cash_slots, len(eco["SlotCashPrices"]))
        if "ExtraSlots" in self.passes:
            n += eco["GamepassSlots"]
        return int(min(n, eco["MaxSlots"]))

    def incubator_count(self) -> int:
        eco = self.c.eco
        n = min(eco["Incubators"] + self.rebirths // eco["RebirthsPerIncubator"], eco["MaxIncubators"])
        return int(n + self.stat("Incubators", self._pas))

    # ---------------------------------------------------------- sweeping
    def sweep(self):
        """Best (cash/s, tiles/s, trip seconds, zone) over owned gear and open zones."""
        c, pas = self.c, self._pas
        power_m = 1 + self.stat("Power", pas)
        size_m = 1 + self.stat("Radius", pas)
        bag_m = 1 + self.stat("Backpack", pas)
        value_m = 1 + self.stat("DustValue", pas)
        crit = self.stat("Crit", pas) * (5 + self.stat("CritMult", pas) - 1)
        gold = 1 + (GOLDEN - 1) * (1 + self.stat("Golden", pas))
        combo = COMBO + 0.15 * self.stat("ComboMax", pas) + 0.05 * self.stat("ComboTime", pas)
        walk = WALK + self.stat("Speed", pas) + (10 if self.boost("Speed") else 0)
        tool = c.tools[self.tier - 1]
        gear = [(tool["Radius"], tool["Power"], tool["Capacity"], walk)]
        for car in c.cars:
            if car["Id"] in self.cars:
                gear.append((car["Radius"], car["Power"], max(car["Capacity"], tool["Capacity"]), car["Speed"]))
        trip = SELL_TRIP_PASS if "SellAnywhere" in self.passes else SELL_TRIP
        eff = EFFICIENCY + (0.15 if "AutoSweep" in self.passes else 0)
        best = (0.0, 0.0, trip, "Landing")
        for r, p, cap, spd in gear:
            r *= size_m
            p *= power_m
            cap *= bag_m
            for z in c.zones:
                if z["Id"] not in self.zones:
                    continue
                hits = math.ceil(z["DustHP"] / p)
                tiles = 2 * r * spd / z["TileSize"] ** 2
                dwell = TICKS * (2 * r / spd)
                if dwell < hits:
                    tiles *= dwell / hits
                tiles = min(tiles * eff, z["Tiles"] / z["RegrowSeconds"] * FIELD_SHARE)
                units = tiles * z["DustPerTile"] * p
                trash = 1 + z.get("TrashPercent", 0) / 100 * (c.eco["TrashMult"] - 1)
                fill = cap / units
                share = fill / (fill + trip)
                cps = units * z["CashMult"] * value_m * combo * gold * trash * (1 + crit) * share
                if cps > best[0]:
                    best = (cps, tiles * share, trip, z["Id"])
        cps, tiles, trip, zone = best
        return cps * self.cash_mult(), tiles, trip, zone, cps

    def pet_income(self, temp=True) -> float:
        return sum(p["income"] for p in self.pets) * (1 + self.stat("PetIncome", self._pas)) * self.cash_mult(temp)

    # ---------------------------------------------------------- eggs and pets
    def roll_rarity(self, max_rarity: str, luck: float) -> str:
        mo = self.c.rorder[max_rarity]
        opts = [(r["Name"], r["Weight"] * (luck if r["Order"] > 1 else 1)) for r in self.c.rarities
                if r["Order"] <= mo and r["Weight"] > 0]
        total = sum(w for _, w in opts)
        x = self.rng.random() * total
        for n, w in opts:
            x -= w
            if x <= 0:
                return n
        return opts[0][0]

    def roll_best(self, max_rarity: str, luck: float, n: int) -> str:
        """Best rarity out of n rolls (inverse CDF: P(best <= k) = F(k)^n)."""
        mo = self.c.rorder[max_rarity]
        opts = [(r["Name"], r["Weight"] * (luck if r["Order"] > 1 else 1)) for r in self.c.rarities
                if r["Order"] <= mo and r["Weight"] > 0]
        total = sum(w for _, w in opts)
        u = self.rng.random()
        acc = 0.0
        for name, w in opts:
            acc += w
            if u <= (acc / total) ** n:
                return name
        return opts[-1][0]

    def pet_rarity(self, egg: str) -> str:
        """Any egg can hatch any rarity (Eggs.hatchOdds / rollPetRarity in Config/Eggs)."""
        c, odds = self.c, self.c.hatch_odds
        if egg == "Cosmic" and self.paid_cosmic > 0:
            self.paid_cosmic -= 1
            return egg
        names = [r["Name"] for r in sorted(c.rarities, key=lambda r: r["Order"])]
        e = int(c.rorder[egg])  # 1-based
        hatch_luck = self.sp.server_luck * (2 if self.boost("Luck2x") else 1)
        boost = max(1.0, hatch_luck) ** 0.5
        p = [0.0] * len(names)
        for k in range(1, len(names) - e + 1):
            p[e - 1 + k] = (odds["Up"][k - 1] if k - 1 < len(odds["Up"]) else 0) * boost
        up = sum(p)
        if up > odds["UpCap"]:
            p = [x * odds["UpCap"] / up for x in p]
            up = odds["UpCap"]
        down = 0.0
        for k in range(1, min(e - 1, len(odds["Down"])) + 1):
            p[e - 1 - k] = odds["Down"][k - 1]
            down += p[e - 1 - k]
        p[e - 1] = 100 - up - down
        roll = self.rng.random() * 100
        for name, chance in zip(names, p):
            roll -= chance
            if roll < 0:
                return name
        return egg

    def hatch(self, rarity: str, zone: str):
        c, rng = self.c, self.rng
        if c.hatch_odds["Up"]:
            rarity = self.pet_rarity(rarity)
        pool = c.pools.get(zone, {}).get(rarity) or c.pools["Landing"].get(rarity) or c.pools["Landing"]["Common"]
        d = rng.choice(pool)
        luck = self.luck()
        inc = d["Income"] * WEIGHT_MULT * rng.uniform(0.85, 1.15)
        for m in sorted(c.mutations, key=lambda m: m["Chance"], reverse=True):
            if rng.random() < min(1, luck / m["Chance"]):
                inc *= m["IncomeMult"]
                break
        huge = rng.random() < min(1, c.huge_chance * luck)
        if huge:
            inc *= c.huge_mult
        pet = {"income": inc, "def": d, "huge": huge}
        if len(self.pets) < self.slots():
            self.pets.append(pet)
        else:
            worst = min(self.pets, key=lambda p: p["income"])
            if inc > worst["income"]:
                self.pets.remove(worst)
                self.pets.append(pet)
        self.best_pet = max(getattr(self, "best_pet", 0), inc)

    def hatch_seconds(self, rarity: str) -> float:
        s = self.c.rhatch[rarity]
        if "FasterHatch" in self.passes:
            s *= self.c.faster_hatch
        return s / (1 + self.stat("HatchSpeed", self._pas)) / WEATHER_GROW

    # ---------------------------------------------------------- shopping
    def candidates(self):
        c, eco = self.c, self.c.eco
        out = []
        if self.tier < len(c.tools):
            out.append((c.tools[self.tier]["Price"], "tool", None))
        for z in c.zones:
            if z["Id"] not in self.zones and z["RequiredRebirths"] <= self.rebirths:
                out.append((z["UnlockCost"], "zone", z["Id"]))
        for car in c.cars:
            if car["Id"] not in self.cars and car["RequiredRebirths"] <= self.rebirths:
                out.append((car["Price"], "car", car["Id"]))
                break
        if self.cash_slots < len(eco["SlotCashPrices"]):
            out.append((eco["SlotCashPrices"][self.cash_slots], "slot", None))
        for u in c.upgrades:
            lvl = self.levels.get(u["Id"], 0)
            if lvl >= u["MaxLevel"] or self.rebirths < u["RequiredRebirths"]:
                continue
            need = u["Parent"] or (c.trees.get(u["Tree"]) if u["Tree"] != "Main" else None)
            if need and self.levels.get(need, 0) < 1:
                continue
            if u["Stat"] in ("Offline",) and not self.pets:
                continue
            out.append((math.floor(u["BaseCost"] * u["CostGrowth"] ** lvl), "up", u["Id"]))
        return out

    def rebirth_cost(self) -> float:
        eco = self.c.eco
        costs = eco["RebirthCosts"]
        if self.rebirths < len(costs):
            return costs[self.rebirths]
        return costs[-1] * eco["RebirthCostGrowth"] ** (self.rebirths - len(costs) + 1)

    def do_rebirth(self, paid=True):
        if paid:
            self.cash = 0
        else:
            self.cash = 0
        self.rebirths += 1
        self.tier = 1
        self.cars = set()
        self.levels = {}
        self._stats = None
        self.mark(f"Rebirth {self.rebirths}" + ("" if paid else " (Robux)"))

    def shop(self):
        sp = self.sp
        if sp.car_unlock and not self.car_bought and self.tier >= self.c.eco["CarRobuxMinTier"]:
            self.car_bought = True
            self.cars.add(sp.car_unlock)
            self.robux += self.c.products["Unlock" + sp.car_unlock]["Price"]
        while True:
            cost = self.rebirth_cost()
            if self.cash >= cost:
                self.do_rebirth()
                continue
            if self.sp.skip_rebirth_at is not None and self.cash >= cost * self.sp.skip_rebirth_at and self._can_skip():
                key = "SkipRebirth" + ("" if self.rebirths == 0 else str(min(self.rebirths + 1, 7)))
                self.robux += self.c.products.get(key, self.c.products["SkipRebirth"])["Price"]
                self.skips_today += 1
                self.do_rebirth(paid=False)
                continue
            cands = [x for x in self.candidates() if x[0] < cost]
            if not cands:
                return
            price, kind, what = min(cands, key=lambda x: x[0])
            if price > self.cash:
                return
            self.cash -= price
            if kind == "tool":
                self.tier += 1
                self.mark(self.c.tools[self.tier - 1]["Name"])
            elif kind == "zone":
                self.zones.add(what)
                self.mark("zone " + next(z["Name"] for z in self.c.zones if z["Id"] == what))
            elif kind == "car":
                self.cars.add(what)
                self.mark("car " + next(v["Name"] for v in self.c.cars if v["Id"] == what))
            elif kind == "slot":
                self.cash_slots += 1
            else:
                self.levels[what] = self.levels.get(what, 0) + 1
                self.spent_upgrades += price
            self._pas = self.passive_bonus()
            self._stats = None

    def _can_skip(self) -> bool:
        return self.skips_today < 1  # one Robux rebirth per day at most

    def mark(self, label: str):
        if not any(l == label for _, l in self.log):
            self.log.append((self.t, label))

    # ---------------------------------------------------------- rewards
    def give_reward(self, r: dict):
        kind = r.get("Kind")
        if kind == "Cash":
            cps = self._last_cps + self.pet_income()
            self.cash += max(cps * r.get("Seconds", 60), 0)  # floor ignored (small)
        elif kind == "Item":
            self.use_item(r["Item"], int(r.get("Amount", 1)))
        elif kind == "Egg":
            self.queue.append((self.c.rorder[r["Rarity"]], r["Rarity"], self.best_zone()))

    def use_item(self, item: str, n: int):
        d = self.c.items.get(item, {})
        for _ in range(n):
            if d.get("Boost"):
                key = d["Boost"]
                self.boosts[key] = max(self.boosts.get(key, self.t), self.t) + d.get("Minutes", 10) * 60
            elif d.get("HatchSeconds"):
                self.incubators = [(e - d["HatchSeconds"], r, z) for e, r, z in self.incubators]

    def best_zone(self) -> str:
        best = "Landing"
        for z in self.c.zones:
            if z["Id"] in self.zones:
                best = z["Id"]
        return best

    # ---------------------------------------------------------- main loop
    def run(self, hours: float):
        self._pas = {}
        self._stats = None
        self._last_cps = 0.0
        self.skips_today = 0
        self.best_pet = 0
        end = hours * 3600
        next_snapshot = 0
        self.snap = []
        session_len = SESSION_HOURS * 3600
        self.new_day()
        while self.t < end:
            cps, tiles, trip, zone, _ = self.sweep()
            self._last_cps = cps
            pets = self.pet_income()
            self.cash += (cps + pets) * STEP
            # eggs found while sweeping
            zdef = next(z for z in self.c.zones if z["Id"] == zone)
            lam = tiles * STEP * zdef["EggChance"] * self.luck()
            n = _poisson(self.rng, lam)
            if n:
                # only the best few eggs of a trip matter: roll best-of-n a few times
                k = min(n, 3)
                for i in range(k):
                    r = self.roll_best(zdef["MaxRarity"], self.luck(), n // k + (1 if i < n % k else 0))
                    self.found.append((self.c.rorder[r], r, zone))
            # trip home: carry the best eggs found since the last trip
            self.since_trip += STEP
            cycle = 45.0 if "SellAnywhere" in self.passes else 30.0
            if self.since_trip >= cycle:
                self.since_trip = 0
                carry = self.c.eco["CarryLimitPass"] if "Carry3" in self.passes else self.c.eco["CarryLimit"]
                self.found.sort(reverse=True)
                self.queue.extend(self.found[: int(carry)])
                self.found = []
                self.queue.sort(reverse=True)
                del self.queue[int(self.c.eco["EggBagSize"]):]
            # incubators
            done = [x for x in self.incubators if x[0] <= self.t]
            self.incubators = [x for x in self.incubators if x[0] > self.t]
            for _, r, z in done:
                self.hatch(r, z)
                self._pas = self.passive_bonus()
            while self.queue and len(self.incubators) < self.incubator_count():
                o, r, z = self.queue.pop(0)
                self.incubators.append((self.t + self.hatch_seconds(r), r, z))
            self.shop()
            self.t += STEP
            self.session_t += STEP
            # playtime gifts
            while self.play_claimed < len(self.c.playtime) and self.session_t >= self.c.playtime[self.play_claimed][0] * 60:
                self.give_reward(self.c.playtime[self.play_claimed][1])
                self.play_claimed += 1
            if self.session_t >= session_len:
                self.offline()
                self.new_day()
            if self.t >= next_snapshot:
                self.snap.append((self.t, cps, pets))
                next_snapshot += 1800

    def offline(self):
        eco = self.c.eco
        cap = eco["OfflineCapSecondsVIP"] if "VIP" in self.passes else eco["OfflineCapSeconds"]
        base = sum(p["income"] for p in self.pets) * (1 + self.stat("PetIncome", self._pas))
        self.cash += base * self.cash_mult(False) * cap * eco["OfflineIncomeRate"] * (1 + self.stat("Offline", self._pas))

    def new_day(self):
        self.day += 1
        self.session_t = 0
        self.play_claimed = 0
        self.skips_today = 0
        if self.daily_i < len(self.c.daily) or True:
            self.give_reward(self.c.daily[self.daily_i % len(self.c.daily)])
            self.daily_i += 1
        for _ in range(self.sp.cash_packs_per_day):
            p = self.c.products[self.sp.cash_pack]
            cps = self._last_cps + self.pet_income()
            self.cash += cps * p["Seconds"]
            self.robux += p["Price"]
        if self.sp.server_luck > 1:
            self.robux += 39  # a 15-minute luck boost a day, averaged over the session


def _poisson(rng: random.Random, lam: float) -> int:
    if lam <= 0:
        return 0
    if lam > 30:
        return max(0, int(rng.gauss(lam, math.sqrt(lam)) + 0.5))
    l, k, p = math.exp(-lam), 0, 1.0
    while True:
        p *= rng.random()
        if p <= l:
            return k
        k += 1


# ---------------------------------------------------------------- report
MILESTONES_ORDER = None


def fmt_h(t: float | None) -> str:
    if t is None:
        return "-"
    if t < 3600:
        return f"{t / 60:.0f}m"
    return f"{t / 3600:.1f}h"


def big(x: float) -> str:
    for unit, n in (("T", 1e12), ("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if x >= n:
            return f"{x / n:.1f}{unit}"
    return f"{x:.0f}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hours", type=float, default=45)
    ap.add_argument("--seeds", type=int, default=12)
    ap.add_argument("--curve", action="store_true", help="print cash/s over time for the free player")
    args = ap.parse_args()
    cfg = Config()
    results = {}
    order: list = []
    for sp in SPENDERS:
        runs = []
        for seed in range(args.seeds):
            p = Player(cfg, sp, random.Random(seed))
            p.run(args.hours)
            runs.append(p)
            for _, l in p.log:
                if l not in order and "(Robux)" not in l:
                    order.append(l)
        results[sp.name] = runs
    # Robux rebirths count as the same milestone
    print(f"{'milestone':24s}" + "".join(f"{s.name:>10s}" for s in SPENDERS))
    for label in order:
        row = f"{label:24s}"
        for sp in SPENDERS:
            ts = []
            for p in results[sp.name]:
                hit = [t for t, l in p.log if l == label or l == label + " (Robux)"]
                if hit:
                    ts.append(hit[0])
            row += f"{fmt_h(statistics.median(ts)) if len(ts) * 2 >= len(results[sp.name]) else '-':>10s}"
        print(row)
    print()
    for sp in SPENDERS:
        runs = results[sp.name]
        rb = statistics.median(p.rebirths for p in runs)
        robux = statistics.median(p.robux for p in runs)
        last = statistics.median(p.snap[-1][1] + p.snap[-1][2] for p in runs)
        petshare = statistics.median(p.snap[-1][2] / max(1, p.snap[-1][1] + p.snap[-1][2]) for p in runs)
        print(f"{sp.name:6s} after {args.hours:.0f} h: rebirths {rb:.0f}, cash/s {big(last)}, pets {petshare:.0%} of income, ~{robux:,.0f} R$")
    if args.curve:
        p = results["free"][0]
        for t, cps, pets in p.snap:
            print(f"{t / 3600:5.1f} h  sweep {big(cps):>8s}/s  pets {big(pets):>8s}/s")


if __name__ == "__main__":
    main()
