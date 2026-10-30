#!/usr/bin/env python3
"""Creates the game passes and developer products listed in src/shared/Config/Products.luau
through Roblox Open Cloud, then writes their IDs back into that file.

Safe to run again: anything already created (matched by name) is reused, and entries that
already have an Id are skipped. Needs ROBLOXAPIKEY in the environment with the
game-pass and developer-product write scopes.

    python3 tools/create_products.py            # create missing, write IDs
    python3 tools/create_products.py --dry-run  # show what would happen
    python3 tools/create_products.py --sync     # also rename existing ones to match the file
    python3 tools/create_products.py --sync --icons  # ...and re-upload their icons
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, "src", "shared", "Config", "Products.luau")
ICONS = os.path.join(ROOT, "art", "out", "icons")
UNIVERSE = "10773346969"
API = "https://apis.roblox.com"

PASS_ICONS = {"Cash2x": "Cash", "AutoSweep": "Auto", "ExtraSlots": "Alien", "Carry3": "Egg",
              "VIP": "Star", "FasterHatch": "Timer", "SellAnywhere": "Sell"}
KIND_ICONS = {"StarterPack": "Gift", "ServerLuck": "Luck", "MeteorShower": "Meteor", "SkipHatch": "Timer",
              "EggPack": "Egg", "ToolSkip": "Tool", "VehicleUnlock": "Vehicle", "VehicleRental": "Vehicle",
              "CashPack": "Cash", "SkipRebirth": "Rebirth", "DoubleOffline": "Cash", "GiftPass": "Gift", "WheelSpins": "Spin"}
KIND_TEXT = {
    "StarterPack": "A bundle to kick off your sweeping run.",
    "ServerLuck": "Boosts egg luck for everyone in the server.",
    "MeteorShower": "Starts an Egg Rain right now: extra eggs fall for everyone.",
    "SkipHatch": "Hatches one egg instantly.",
    "EggPack": "Rare eggs delivered straight to your bag.",
    "ToolSkip": "Unlocks the next sweeping tool right away.",
    "VehicleUnlock": "Unlocks this car in the Garage until your next rebirth.",
    "VehicleRental": "Rents this car until you leave or rebirth.",
    "CashPack": "A pile of cash that grows with your progress.",
    "SkipRebirth": "Rebirth now without meeting the cash goal.",
    "DoubleOffline": "Doubles your welcome-back offline earnings.",
    "GiftPass": "Gifts this gamepass to a friend in your server. It unlocks for them for good.",
    "WheelSpins": "Spins for the Lucky Wheel: cash, potions and eggs, up to a Legendary Egg.",
}

LINE = re.compile(r'\{ Key = "(?P<key>\w+)", Id = (?P<id>\d+), Price = (?P<price>\d+), Name = "(?P<name>[^"]*)"(?P<rest>[^\n]*)')


def curl(method, path, form=None):
    key = os.environ.get("ROBLOXAPIKEY")
    if not key:
        sys.exit("ROBLOXAPIKEY is not set")
    cmd = ["curl", "-sS", "-X", method, "-H", "x-api-key: " + key, "-w", "\n%{http_code}", API + path]
    for name, value in (form or {}).items():
        cmd += ["-F", f"{name}={value}"]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    body, _, code = out.rpartition("\n")
    if not code.startswith("2"):
        raise RuntimeError(f"{method} {path} -> {code}: {body[:300]}")
    return json.loads(body) if body.strip() else {}


def list_all(path, field):
    items, token = [], ""
    while True:
        page = curl("GET", f"{path}?pageSize=50" + (f"&pageToken={token}" if token else ""))
        items += page.get(field) or []
        token = page.get("nextPageToken") or ""
        if not token:
            return items


def icon_form(name):
    path = os.path.join(ICONS, name + ".png")
    return {"imageFile": f"@{path};type=image/png"} if os.path.exists(path) else {}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--sync", action="store_true")
    parser.add_argument("--icons", action="store_true")
    args = parser.parse_args()

    source = open(CONFIG, encoding="utf-8").read()
    passes_src, products_src = source.split("local Products:", 1)

    base = f"/game-passes/v1/universes/{UNIVERSE}/game-passes"
    existing_passes = {p["name"]: p for p in list_all(base + "/creator", "gamePasses")}
    pbase = f"/developer-products/v2/universes/{UNIVERSE}/developer-products"
    existing_products = {p["name"]: p for p in list_all(pbase + "/creator", "developerProducts")}

    ids = {}  # key -> id
    for m in LINE.finditer(passes_src):
        key, name, price = m["key"], m["name"], int(m["price"])
        if m["id"] != "0":
            continue
        desc = re.search(r'Description = "([^"]*)"', m["rest"])
        found = existing_passes.get(name)
        if found:
            ids[key] = found.get("gamePassId") or found.get("id")
            print(f"pass {key}: reuse {ids[key]}")
            continue
        print(f"pass {key}: create '{name}' R${price}")
        if args.dry_run:
            continue
        form = {"name": name, "description": desc[1] if desc else name, "price": price, "isForSale": "true"}
        form.update(icon_form(PASS_ICONS.get(key, "Star")))
        made = curl("POST", base, form)
        ids[key] = made.get("gamePassId") or made.get("id")
        print("   ->", ids[key])
        time.sleep(0.4)

    for m in LINE.finditer(products_src):
        key, name, price = m["key"], m["name"], int(m["price"])
        if m["id"] != "0":
            continue
        kind = re.search(r'Kind = "(\w+)"', m["rest"])[1]
        found = existing_products.get(name)
        if found:
            ids[key] = found["productId"]
            print(f"product {key}: reuse {ids[key]}")
            continue
        print(f"product {key}: create '{name}' R${price}")
        if args.dry_run:
            continue
        form = {"name": name, "description": KIND_TEXT.get(kind, name), "price": price, "isForSale": "true"}
        form.update(icon_form(KIND_ICONS.get(kind, "Shop")))
        made = curl("POST", pbase, form)
        ids[key] = made["productId"]
        print("   ->", ids[key])
        time.sleep(0.4)

    if args.sync:
        sync(passes_src, products_src, base, pbase, args)

    if args.dry_run or not ids:
        return

    def fill(match):
        if match["key"] in ids and match["id"] == "0":
            return match[0].replace("Id = 0,", f"Id = {ids[match['key']]},", 1)
        return match[0]

    out = LINE.sub(fill, source)
    out = out.replace(" -- TODO(Dev)", "")
    out = out.replace("\t-- TODO(Dev): every Id below is a placeholder.\n", "")
    out = out.replace("-- TODO(Dev): create these in the Creator Dashboard (universe 10773346969) and paste the IDs.\n",
                      "-- Created through Open Cloud by tools/create_products.py (universe 10773346969).\n")
    open(CONFIG, "w", encoding="utf-8").write(out)
    print(f"wrote {len(ids)} ids to {os.path.relpath(CONFIG, ROOT)}")


def sync(passes_src, products_src, base, pbase, args):
    """Rename (and optionally re-icon) passes and products that already exist, so the names
    players see in purchase prompts match Products.luau."""
    by_id = {str(p.get("gamePassId") or p.get("id")): p for p in list_all(base + "/creator", "gamePasses")}
    for m in LINE.finditer(passes_src):
        if m["id"] == "0":
            continue
        desc = re.search(r'Description = "([^"]*)"', m["rest"])
        want = {"name": m["name"], "description": desc[1] if desc else m["name"]}
        have = by_id.get(m["id"], {})
        if have.get("name") == want["name"] and have.get("description") == want["description"] and not args.icons:
            continue
        print(f"pass {m['key']}: '{have.get('name')}' -> '{want['name']}'")
        if args.dry_run:
            continue
        form = dict(want)
        if args.icons:
            form.update(icon_form(PASS_ICONS.get(m["key"], "Star")))
        curl("PATCH", f"{base}/{m['id']}", form)
        time.sleep(0.4)
    by_id = {str(p["productId"]): p for p in list_all(pbase + "/creator", "developerProducts")}
    for m in LINE.finditer(products_src):
        if m["id"] == "0":
            continue
        kind = re.search(r'Kind = "(\w+)"', m["rest"])[1]
        want = {"name": m["name"], "description": KIND_TEXT.get(kind, m["name"])}
        have = by_id.get(m["id"], {})
        if have.get("name") == want["name"] and have.get("description") == want["description"] and not args.icons:
            continue
        print(f"product {m['key']}: '{have.get('name')}' -> '{want['name']}'")
        if args.dry_run:
            continue
        form = dict(want)
        if args.icons:
            form.update(icon_form(KIND_ICONS.get(kind, "Shop")))
        curl("PATCH", f"{pbase}/{m['id']}", form)
        time.sleep(0.4)


if __name__ == "__main__":
    main()
