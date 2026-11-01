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
    # 2026-11-01 retention pass. Times are for a free kid on a phone, with the learning ramp
    # in sim.efficiency (calibrated on real saves). Psychology behind the spacing:
    #   0-5 min   something new every 1-1.5 min, and a new area (Park) before the 5-minute
    #             mark, where 79% of players used to leave.
    #   5-30 min  a new tool every 3-5 min, the Beach as the first-session "big goal".
    #   30-80 min the slower rest of the ladder and the cars; Rebirth 1 lands near the end of
    #             a long first day or early on day 2, so day 2 starts with a reset + x1.5 cash.
    #   later     a rebirth or a zone every 1-3 play hours (one or two per daily session).
    # The Broom is free (tutorial), so it is not fitted.
    "Rake": 2.5 / 60,
    "Mop": 3.5 / 60,
    "zone Park": 5 / 60,
    "Push Broom": 6.5 / 60,
    "Leaf Blower": 8.5 / 60,
    "Leaf Vacuum": 11 / 60,
    "Shop Vac": 14 / 60,
    "Pressure Washer": 18 / 60,
    "zone Beach": 22 / 60,
    "Turbo Vacuum": 27 / 60,
    "Golden Broom": 32 / 60,
    "Storm Blower": 37 / 60,
    "car Sweeper Cart": 42 / 60,
    "Tornado Vac": 47 / 60,
    "car Golf Cart": 52 / 60,
    "Diamond Mop": 57 / 60,
    "Rainbow Duster": 63 / 60,
    "Galaxy Vacuum": 70 / 60,
    "Rebirth 1": 1.25,
    "zone City": 2.0,
    "car Garbage Truck": 2.6,
    "Rebirth 2": 3.2,
    "car Street Sweeper": 4.2,
    "Rebirth 3": 5.5,
    "zone Snowy Peaks": 7.0,
    "car Lawn Tractor": 7.5,
    "Rebirth 4": 9.0,
    "car Snow Plow": 10.5,
    "Rebirth 5": 12.5,
    "car Mega Sweeper": 14.5,
    "Rebirth 6": 17.0,
    "Rebirth 7": 22.0,
    "Rebirth 8": 28.0,
    "Rebirth 9": 35.0,
    "Rebirth 10": 44.0,
}
HOURS = 50
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
