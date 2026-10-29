"""Build the place from the repo with Rojo and publish it to the live game.

  python3 tools/publish_place.py            # build + publish (needs ROBLOXAPIKEY)
  python3 tools/publish_place.py --build    # only build build/GameDev.rbxl

Needs rojo 7.4 (`cargo install rojo --version 7.4.4 --locked`). The repo's UI and world
JSON uses LiveSync's value forms (hex colours, nested UDim2 lists...), so tools/rojo_tree.py
first writes a Rojo-ready copy of the tree to build/rojo/.
Publishing fails with 409 "server is busy" while the place itself is open in Studio.
"""
import os, subprocess, sys, urllib.request

UNIVERSE, PLACE = 10773346969, 135673665804657
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
TREE = os.path.join(BUILD, "rojo")
OUT = os.path.join(BUILD, "GameDev.rbxl")

subprocess.run([sys.executable, os.path.join(ROOT, "tools", "rojo_tree.py"), ROOT, TREE], check=True)
rojo = os.path.expanduser("~/.cargo/bin/rojo") if os.path.exists(os.path.expanduser("~/.cargo/bin/rojo")) else "rojo"
subprocess.run([rojo, "build", "default.project.json", "-o", OUT], cwd=TREE, check=True)
if "--build" in sys.argv:
    sys.exit(0)
req = urllib.request.Request(
    f"https://apis.roblox.com/universes/v1/{UNIVERSE}/places/{PLACE}/versions?versionType=Published",
    data=open(OUT, "rb").read(), method="POST",
    headers={"x-api-key": os.environ["ROBLOXAPIKEY"], "Content-Type": "application/octet-stream"})
print(urllib.request.urlopen(req).read().decode())
