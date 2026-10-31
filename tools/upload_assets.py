"""Upload built art to Roblox and write src/shared/Config/Assets.luau.

  python3 tools/upload_assets.py            # upload new/changed files only
  python3 tools/upload_assets.py --force X  # re-upload names containing X
  python3 tools/upload_assets.py --creator 123  # upload as another Roblox user

  python3 tools/upload_assets.py --write-lua    # only rewrite Assets.luau from the locks
  python3 tools/upload_assets.py --grant-all    # re-grant every asset in the lock (see GRANTS)

Every new upload is granted to the game (with the meshes/textures inside it), the alt
account and the group in GRANTS right away.

Needs env ROBLOXAPIKEY (Open Cloud key with asset write, belonging to the creator).
The key is never printed. Uploads are cached by file hash per creator in
art/assets.lock.json (default account) or art/assets.<creator>.lock.json, so unchanged
files are skipped.
Config/Assets.luau is built from art/assets.accounts.json: ids come from the "primary"
account, with the "fallback" account's ids kept for when the primary ones can't load
(a game can only insert models and play animations owned by its own creator).
Models: art/out/*.glb (Model). Animations: art/out/anims/*.rbxmx (Animation).
Images: art/out/icons/*.png and art/out/ui/*.png (Image).
"""
import hashlib
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.request
import uuid

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "art", "out")
LUA = os.path.join(ROOT, "src", "shared", "Config", "Assets.luau")
DEFAULT_CREATOR = "822623546"
CREATOR_USER_ID = sys.argv[sys.argv.index("--creator") + 1] if "--creator" in sys.argv else DEFAULT_CREATOR
ACCOUNTS = os.path.join(ROOT, "art", "assets.accounts.json")


def lock_path(creator):
    return os.path.join(ROOT, "art", "assets.lock.json" if creator == DEFAULT_CREATOR else f"assets.{creator}.lock.json")


def read_lock(creator):
    path = lock_path(creator)
    lock = json.load(open(path)) if os.path.exists(path) else {}
    for k in ("models", "anims", "images"):
        lock.setdefault(k, {})
    return lock


LOCK = lock_path(CREATOR_USER_ID)
ONLY = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
PREFIX = "SweepMoon_"


def ctx():
    for p in (os.environ.get("SSL_CERT_FILE"), "/root/.ccr/ca-bundle.crt"):
        if p and os.path.exists(p):
            return ssl.create_default_context(cafile=p)
    return ssl.create_default_context()


CTX = ctx()


def request(method, url, body=None, headers=None):
    h = {"x-api-key": os.environ["ROBLOXAPIKEY"]}
    h.update(headers or {})
    r = urllib.request.Request(url, data=body, method=method, headers=h)
    try:
        with urllib.request.urlopen(r, context=CTX, timeout=180) as resp:
            data = resp.read()
            return resp.status, json.loads(data) if data else {}
    except urllib.error.HTTPError as e:
        data = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(data)
        except Exception:
            return e.code, {"raw": data[:500]}


def upload(path, asset_type, name):
    ct = {".glb": "model/gltf-binary", ".rbxmx": "model/x-rbxm", ".png": "image/png", ".jpg": "image/jpeg"}[os.path.splitext(path)[1]]
    meta = {"assetType": asset_type, "displayName": (PREFIX + name)[:50], "description": f"Sweep the Moon: {name}",
            "creationContext": {"creator": {"userId": CREATOR_USER_ID}}}
    b = uuid.uuid4().hex
    body = (f"--{b}\r\nContent-Disposition: form-data; name=\"request\"\r\nContent-Type: application/json\r\n\r\n"
            f"{json.dumps(meta)}\r\n--{b}\r\nContent-Disposition: form-data; name=\"fileContent\"; "
            f"filename=\"{os.path.basename(path)}\"\r\nContent-Type: {ct}\r\n\r\n").encode() + open(path, "rb").read() + f"\r\n--{b}--\r\n".encode()
    for attempt in range(5):
        code, op = request("POST", "https://apis.roblox.com/assets/v1/assets", body, {"Content-Type": f"multipart/form-data; boundary={b}"})
        if code == 429 or code >= 500:
            time.sleep(2 ** attempt * 2)
            continue
        break
    if code >= 300:
        raise RuntimeError(f"upload {name} failed: {code} {op}")
    path_ = op.get("path")
    for _ in range(90):
        if op.get("done"):
            break
        time.sleep(2)
        code, op = request("GET", f"https://apis.roblox.com/assets/v1/{path_}")
    resp = op.get("response") or {}
    if not resp.get("assetId"):
        raise RuntimeError(f"upload {name}: no asset id ({op})")
    return int(resp["assetId"])


# Who may use every upload, granted right after it finishes (Dev, 2026-10-29). The game
# (universe) also gets the meshes and textures inside each model (grantToDependencies; the
# API only allows that for a universe), or Studio shows "not authorized" for those inner ids
# and the model draws as nothing. The alt account and the group get the asset itself.
GRANTS = [("Universe", "10773346969", True), ("User", "347852675", False), ("Group", "351097046", False)]


def grant(ids, tries=6):
    """Grants Use to every GRANTS subject. A model that was just uploaded can answer
    CannotManageAsset for a little while (2026-10-31: 5 tool models ended up ungranted and
    "not authorized" in Studio), so those are retried a few times, 10 s apart."""
    ids = [int(i) for i in ids]
    for subject, sid, deps in GRANTS:
        todo = list(ids)
        for attempt in range(tries):
            retry = []
            for i in range(0, len(todo), 50):
                body = {"subjectType": subject, "subjectId": sid, "action": "Use",
                        "requests": [{"assetId": a, "grantToDependencies": deps} for a in todo[i:i + 50]]}
                code, r = request("PATCH", "https://apis.roblox.com/asset-permissions-api/v1/assets/permissions",
                                  json.dumps(body).encode(), {"Content-Type": "application/json-patch+json"})
                errs = r.get("errors") if isinstance(r, dict) else None
                if code >= 300:
                    print(f"  grant to {subject} {sid}: {code} {r}", flush=True)
                for e in errs or []:
                    if isinstance(e, dict) and e.get("code") == "CannotManageAsset" and attempt < tries - 1:
                        retry.append(int(e["assetId"]))
                    else:
                        print(f"  grant to {subject} {sid}: {e}", flush=True)
            if not retry:
                break
            todo = retry
            time.sleep(10)


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def lua_value(v, indent=1):
    pad = "\t" * indent
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return "nil"
    if isinstance(v, (int, float)):
        return repr(round(v, 4)) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        if len(v) == 3 and all(isinstance(x, (int, float)) for x in v):
            return f"Vector3.new({', '.join(lua_value(float(x)) for x in v)})"
        return "{ " + ", ".join(lua_value(x, indent + 1) for x in v) + " }"
    if isinstance(v, dict):
        items = []
        for k in sorted(v):
            if v[k] is None:
                continue
            key = k if k.isidentifier() else f'["{k}"]'
            items.append(f"{pad}\t{key} = {lua_value(v[k], indent + 1)},")
        return "{\n" + "\n".join(items) + f"\n{pad}}}"
    raise TypeError(type(v))


def write_lua(meta):
    accounts = json.load(open(ACCOUNTS)) if os.path.exists(ACCOUNTS) else {"primary": DEFAULT_CREATOR}
    primary = read_lock(str(accounts["primary"]))
    fb_creator = accounts.get("fallback")
    fallback = read_lock(str(fb_creator)) if fb_creator and str(fb_creator) != str(accounts["primary"]) else None

    def pick(bucket, name):
        # (id, fallback id) for one asset; fallback is None when it isn't needed.
        main = primary[bucket].get(name)
        alt = fallback[bucket].get(name) if fallback else None
        if not main:
            return (alt["id"] if alt else None), None
        return main["id"], (alt["id"] if alt and alt["id"] != main["id"] else None)

    def names(bucket):
        return sorted(set(primary[bucket]) | set(fallback[bucket] if fallback else ()))

    models, anims, anim_fb, images = {}, {}, {}, {}
    for name in names("models"):
        m = dict(meta.get(name, {}))
        m.pop("name", None)
        m.pop("tris", None)
        m["id"], m["fallback"] = pick("models", name)
        models[name] = m
    for name in names("anims"):
        anims[name], fb = pick("anims", name)
        if fb:
            anim_fb[name] = fb
    for name in names("images"):
        images[name] = f"rbxassetid://{pick('images', name)[0]}"
    src = ["--!strict",
           "-- GENERATED by tools/upload_assets.py from art/out. Do not edit by hand.",
           "-- Model ids are Roblox Model assets (GLB from art/blender), loaded by AssetService.",
           "-- id = primary account upload, fallback = same model from the fallback account",
           "-- (art/assets.accounts.json). AssetService tries id first, then fallback.",
           "-- Part data: parent = rig parent, joint = Motor6D pivot (model space), glow = Neon colour.",
           "local Assets = {}",
           "",
           f"Assets.Models = {lua_value(models, 0)}",
           "",
           f"Assets.Animations = {lua_value(anims, 0)}",
           "",
           "-- Used instead of Assets.Animations when the primary account's models failed to load",
           "-- (same owner rule as models). AssetService sets ReplicatedStorage.Assets.UseFallback.",
           f"Assets.AnimationFallback = {lua_value(anim_fb, 0)}",
           "",
           "-- UI images (icons rendered in art/blender/icons.py, UI art from art/out/ui).",
           f"Assets.Images = {lua_value(images, 0)}",
           "",
           "return Assets",
           ""]
    open(LUA, "w").write("\n".join(src))


def main():
    force = sys.argv[sys.argv.index("--force") + 1] if "--force" in sys.argv else None
    meta = json.load(open(os.path.join(OUT, "meta.json")))
    if "--write-lua" in sys.argv:
        write_lua(meta)
        print("wrote", os.path.relpath(LUA, ROOT))
        return
    lock = read_lock(CREATOR_USER_ID)
    if "--grant-all" in sys.argv:
        ids = [v["id"] for bucket in ("models", "anims", "images") for v in lock[bucket].values()]
        grant(ids)
        print(f"granted {len(ids)} assets")
        return
    jobs = []
    for f in sorted(os.listdir(OUT)):
        if f.endswith(".glb") and f[:-4] in meta:
            jobs.append(("models", "Model", f[:-4], os.path.join(OUT, f)))
    adir = os.path.join(OUT, "anims")
    if os.path.isdir(adir):
        for f in sorted(os.listdir(adir)):
            if f.endswith(".rbxmx"):
                jobs.append(("anims", "Animation", f[:-6], os.path.join(adir, f)))
    for sub, prefix in (("icons", "Icon_"), ("ui", "")):
        d = os.path.join(OUT, sub)
        if os.path.isdir(d):
            for f in sorted(os.listdir(d)):
                if f.endswith((".png", ".jpg")):
                    jobs.append(("images", "Image", prefix + os.path.splitext(f)[0], os.path.join(d, f)))
    changed = 0
    for bucket, kind, name, path in jobs:
        h = sha(path)
        old = lock[bucket].get(name)
        if old and old["sha"] == h and not (force and force in name):
            continue
        if ONLY and ONLY != name:
            continue
        aid = upload(path, kind, name)
        grant([aid])
        lock[bucket][name] = {"id": aid, "sha": h}
        changed += 1
        print(f"uploaded {name} -> {aid}", flush=True)
        json.dump(lock, open(LOCK, "w"), indent=1, sort_keys=True)
    if not ONLY and "--only-lock" not in sys.argv:
        write_lua(meta)
    print(f"done: {changed} uploaded, {len(jobs) - changed} unchanged")


if __name__ == "__main__":
    main()
