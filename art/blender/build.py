"""Build every asset to art/out/<Name>.glb plus art/out/meta.json.

Usage (headless Blender as a Python module, or inside Blender's Python):
  python art/blender/build.py [filter ...]
"""
import os
import sys
import json
import bpy  # noqa: F401  (loads mathutils)

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import aliens  # noqa: E402
import props  # noqa: E402
import litter  # noqa: E402
import piles  # noqa: E402
import rocks  # noqa: E402
import coins  # noqa: E402

OUT = os.path.join(HERE, "..", "out")


def builders():
    for k, fn in aliens.ALL.items():
        yield f"Alien_{k}", fn
    for k, fn in aliens.VARIANTS.items():
        yield f"Alien_{k}", fn
    for k, fn in props.ALL.items():
        yield k, fn
    for k, fn in litter.ALL.items():
        yield k, fn
    for k, fn in piles.ALL.items():
        yield k, fn
    for k, fn in rocks.ALL.items():
        yield k, fn
    for k, fn in coins.ALL.items():
        yield k, fn


def main(filters):
    os.makedirs(OUT, exist_ok=True)
    meta_path = os.path.join(OUT, "meta.json")
    meta = {}
    if os.path.exists(meta_path):
        meta = json.load(open(meta_path))
    for name, fn in builders():
        if filters and not any(f.lower() in name.lower() for f in filters):
            continue
        a = fn()
        path, m = a.export(OUT)
        meta[name] = m
        print(f"built {name}: {m['tris']} tris, {len(m['parts'])} parts")
    json.dump(meta, open(meta_path, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    main(sys.argv[1:])
