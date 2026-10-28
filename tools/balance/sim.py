"""Rough progression model for Sweep the Moon: how long until each tool, zone, car and
rebirth for a kid who sweeps nonstop and sells when full (pets, gifts and boosts ignored,
so real play is a bit faster). Target: first rebirth around 2 h, rebirth 5 around 18 h,
rebirth 7 around 40 h, so a release lasts about a week of after-school play. Keep the tables in sync with src/shared/Config/*.luau.

    python3 tools/balance/sim.py
"""
WALK = 16           # studs/s
TICKS = 10          # sweep ticks per second
SELL_TRIP = 8       # seconds lost per sell (teleport to the rocket and back)
COMBO = 1.6         # average combo multiplier while sweeping (x1..x3)
GOLDEN = 1.15       # golden piles and dust bunnies on top
EFFICIENCY = 0.6    # kids wander, chat, open menus

# name, radius, power, capacity, price
TOOLS = [
    ("Toothbrush", 4, 1, 40, 0),
    ("Broom", 5, 2, 120, 120),
    ("Mop", 6, 4, 350, 1_200),
    ("Leaf Blower", 8, 8, 1_200, 40_000),
    ("Shop Vac", 10, 16, 4_000, 220_000),
    ("Turbo Vacuum", 12, 32, 14_000, 4_500_000),
]
# name, radius, power, capacity, price, rebirths needed
CARS = [
    ("Sweeper Cart", 14, 50, 40_000, 20_000_000, 0),
    ("Moon Buggy", 16, 90, 90_000, 50_000_000, 0),
    ("Dust Truck", 20, 180, 250_000, 1_200_000_000, 1),
    ("Hover Sweeper", 24, 400, 700_000, 20_000_000_000, 2),
    ("Moon Crawler", 28, 900, 2_000_000, 240_000_000_000, 3),
    ("Solar Rover", 32, 2_000, 6_000_000, 3_000_000_000_000, 4),
    ("Rocket Sweeper", 38, 5_000, 20_000_000, 37_500_000_000_000, 5),
]
# name, tile size, hp, dust per tile, cash per dust, unlock price, rebirths needed
ZONES = [
    ("Landing", 4, 1, 1, 1, 0, 0),
    ("Crater", 5, 6, 3, 4, 6_000, 0),
    ("DarkSide", 6, 30, 7, 15, 900_000, 0),
    ("Mars", 6, 150, 11, 60, 400_000_000, 1),
    ("Europa", 6, 700, 16, 250, 120_000_000_000, 3),
]
REBIRTH_BASE = 150_000_000
REBIRTH_GROWTH = 7
REBIRTH_BONUS = 0.5


def rate(r, p, cap, zone):
    _, ts, hp, dpt, cpd = zone[:5]
    hits = -(-hp // p)
    tiles = 2 * r * WALK / ts ** 2
    dwell = TICKS * (2 * r / WALK)
    if dwell < hits:
        tiles *= dwell / hits
    units = tiles * dpt * p
    fill = cap / units
    return units * cpd * COMBO * GOLDEN * EFFICIENCY * fill / (fill + SELL_TRIP)


def main():
    t, cash, rebirths = 0.0, 0.0, 0
    tier, cars, zones = 0, 0, {"Landing"}
    print(f"{'event':30s} {'play time':>10s}  {'cash/s':>14s}")
    while rebirths < 7:
        mult = 1 + REBIRTH_BONUS * rebirths
        gear = [TOOLS[tier][1:4]] + ([CARS[cars - 1][1:4]] if cars else [])
        cps = max(rate(*g, z) for g in gear for z in ZONES if z[0] in zones) * mult
        goals = []
        if tier + 1 < len(TOOLS):
            goals.append((TOOLS[tier + 1][4], "tool"))
        for z in ZONES:
            if z[0] not in zones and z[6] <= rebirths:
                goals.append((z[5], "zone", z[0]))
        if cars < len(CARS) and CARS[cars][5] <= rebirths:
            goals.append((CARS[cars][4], "car"))
        cost = REBIRTH_BASE * REBIRTH_GROWTH ** rebirths
        goals.append((cost, "rebirth"))
        goal = min(goals, key=lambda g: g[0])
        t += max(0.0, goal[0] - cash) / cps
        cash = max(0.0, cash - goal[0])
        if goal[1] == "tool":
            tier += 1
            label = TOOLS[tier][0]
        elif goal[1] == "zone":
            zones.add(goal[2])
            label = "zone " + goal[2]
        elif goal[1] == "car":
            cars += 1
            label = "car " + CARS[cars - 1][0]
        else:
            rebirths += 1
            tier, cars, cash = 0, 0, 0.0
            label = f"REBIRTH {rebirths}"
        h = t / 3600
        print(f"{label:30s} {h:7.2f} h   {cps:14,.0f}")


if __name__ == "__main__":
    main()
