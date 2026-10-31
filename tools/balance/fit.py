"""Fits prices (tools, zones, cars, rebirths) so a free player hits each milestone near its
target play time. Multipliers (tool stats, zone value, pets, upgrade tree) stay as they
are in the configs; only prices move. Prints the fitted prices to paste into the configs.

    python3 tools/balance/fit.py
"""

from __future__ import annotations

import math
import random
import re
import sys
import statistics
from multiprocessing import Pool

import sim

# milestone -> target play time in hours (free player, 1.5 h sessions a day)
TARGETS = {
    # 16 hand tools (2026-10-31): a new tool every few minutes, the whole ladder done just
    # before the first rebirth.
    "Broom": 0.5 / 60,
    "Rake": 1.5 / 60,
    "Mop": 3 / 60,
    "zone Park": 5 / 60,
    "Push Broom": 7.5 / 60,
    "Leaf Blower": 11 / 60,
    "Leaf Vacuum": 15 / 60,
    "Shop Vac": 19 / 60,
    "Pressure Washer": 24 / 60,
    "zone Beach": 29 / 60,
    "Turbo Vacuum": 34 / 60,
    "Golden Broom": 40 / 60,
    "Storm Blower": 46 / 60,
    "car Sweeper Cart": 52 / 60,
    "Tornado Vac": 58 / 60,
    "car Golf Cart": 64 / 60,
    "Diamond Mop": 70 / 60,
    "Rainbow Duster": 77 / 60,
    "Galaxy Vacuum": 84 / 60,
    "Rebirth 1": 1.5,
    "zone City": 2.5,
    "car Garbage Truck": 3.1,
    "Rebirth 2": 4.0,
    "car Street Sweeper": 5.0,
    "Rebirth 3": 6.5,
    "zone Snowy Peaks": 8.0,
    "car Lawn Tractor": 8.5,
    "Rebirth 4": 10.0,
    "car Snow Plow": 11.5,
    "Rebirth 5": 14.0,
    "car Mega Sweeper": 16.0,
    "Rebirth 6": 19.0,
    "Rebirth 7": 25.0,
    "Rebirth 8": 32.0,
    "Rebirth 9": 40.0,
    "Rebirth 10": 50.0,
}
HOURS = 56
SEEDS = 6
ROUNDS = 8


def params(cfg: sim.Config) -> dict:
    """milestone -> (getter, setter) on the live config."""
    out = {}
    for i, t in enumerate(cfg.tools[1:], start=1):
        out[t["Name"]] = (t, "Price")
    for z in cfg.zones[1:]:
        out["zone " + z["Name"]] = (z, "UnlockCost")
    for v in cfg.cars:
        out["car " + v["Name"]] = (v, "Price")
    eco = cfg.eco
    while len(eco["RebirthCosts"]) < 10:
        eco["RebirthCosts"].append(eco["RebirthCosts"][-1] * eco["RebirthCostGrowth"])
    for i in range(10):
        out[f"Rebirth {i + 1}"] = (eco["RebirthCosts"], i)
    return out


def _run(args):
    cfg, seed = args
    p = sim.Player(cfg, sim.SPENDERS[0], random.Random(seed))
    p.run(HOURS)
    times = {}
    for t, label in p.log:
        times.setdefault(label.replace(" (Robux)", ""), t / 3600)
    return times


def measure(cfg, pool) -> dict:
    runs = pool.map(_run, [(cfg, s) for s in range(SEEDS)])
    out = {}
    for label in TARGETS:
        ts = [r[label] for r in runs if label in r]
        out[label] = statistics.median(ts) if len(ts) * 2 >= len(runs) else None
    return out


def main():
    cfg = sim.Config()
    ps = params(cfg)
    order = list(TARGETS)
    with Pool(4) as pool:
        for rnd in range(ROUNDS):
            got = measure(cfg, pool)
            err = []
            prev_t, prev_a = 0.0, 0.0
            for label in order:
                obj, key = ps[label]
                target, actual = TARGETS[label], got[label]
                if actual is None:
                    f = 0.4
                else:
                    gap_t = max(target - prev_t, 1e-3)
                    gap_a = max(actual - prev_a, 1e-3)
                    f = (gap_t / gap_a) ** 0.5
                    err.append(abs(math.log(actual / target)))
                    prev_a = actual
                prev_t = target
                f = min(4.0, max(0.25, f))
                obj[key] = obj[key] * f
            worst = max(err) if err else 9
            print(f"round {rnd}: mean |log err| {statistics.mean(err) if err else 9:.3f}, worst {worst:.3f}", flush=True)
        got = measure(cfg, pool)
    print()
    print(f"{'milestone':22s} {'target':>8s} {'got':>8s}  price")
    for label in order:
        obj, key = ps[label]
        print(f"{label:22s} {sim.fmt_h(TARGETS[label] * 3600):>8s} {sim.fmt_h(got[label] * 3600 if got[label] else None):>8s}  {obj[key]:,.0f}")
    if "--write" in sys.argv:
        write(cfg)


def nice(x: float) -> int:
    """Two significant figures: 2_569_477 -> 2_600_000."""
    if x < 100:
        return int(round(x))
    e = 10 ** (int(math.log10(x)) - 1)
    return int(round(x / e) * e)


def lua_num(x: int) -> str:
    return f"{x:_}"


def write(cfg: sim.Config):
    """Writes the fitted prices back into the Luau configs."""
    tools = (sim.CFG / "Tools.luau").read_text()
    for t in cfg.tools[1:] + cfg.cars:
        tools = re.sub(r'(Id = "' + t["Id"] + r'".*?Price = )[\d_]+', lambda m: m.group(1) + lua_num(nice(t["Price"])), tools, count=1)
    (sim.CFG / "Tools.luau").write_text(tools)
    zones = (sim.CFG / "Zones.luau").read_text()
    for z in cfg.zones[1:]:
        zones = re.sub(r'(Id = "' + z["Id"] + r'".*?UnlockCost = )[\d_]+', lambda m: m.group(1) + lua_num(nice(z["UnlockCost"])), zones, count=1, flags=re.S)
    (sim.CFG / "Zones.luau").write_text(zones)
    eco = (sim.CFG / "Economy.luau").read_text()
    costs = ", ".join(lua_num(nice(c)) for c in cfg.eco["RebirthCosts"])
    eco = re.sub(r"RebirthCosts = \{[^}]*\}", "RebirthCosts = {\n\t\t" + costs.replace(", ", ",\n\t\t") + ",\n\t}", eco)
    (sim.CFG / "Economy.luau").write_text(eco)
    print("wrote Tools.luau, Zones.luau, Economy.luau")


if __name__ == "__main__":
    main()
