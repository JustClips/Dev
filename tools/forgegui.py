#!/usr/bin/env python3
"""ForgeGUI key pool + client for any Claude session in this project.

Keys live OUTSIDE git, in the project's shared folder:
  /mnt/project-files/secrets/forgegui-keys.json   (override with env FORGEGUI_KEYS_FILE)
The file holds the keys plus what we know about each one (balance, refill date, cost per
generation type). Never print a full key, never copy keys into the repo or into memory.

Commands
  python3 tools/forgegui.py add KEY [KEY ...]       add keys (duplicates ignored)
  python3 tools/forgegui.py status                  table: key id, state, balance, refill date
  python3 tools/forgegui.py probe [--all]           check keys for free (no credits spent);
                                                    by default only keys that are empty/unknown
                                                    or whose refill date has passed
  python3 tools/forgegui.py pick [--need N]         print the id of the key that would be used
  python3 tools/forgegui.py call TOOL 'JSON'        run any ForgeGUI MCP tool with the pool
  python3 tools/forgegui.py image OUT_DIR --type thumbnail --prompt "..." [--ref FILE ...]
        [--count N] [--style "..."] [--id REQUEST_ID]
                                                    generate, wait, download PNGs. --ref files are
                                                    uploaded to whichever account runs the job
                                                    (asset ids are per account), cached per key.

How a key is picked: the least-spent key with credits first, so parallel jobs spread across
accounts (ForgeGUI charges when a job finishes, so stacking jobs on one key can overdraw it). A call that comes
back insufficient_credits records that key's real balance and refill date, marks it empty
and retries on the next key. Empty keys come back by themselves once their refill date
passes (the next pick/probe re-checks them).

Python use:  sys.path.insert(0, "tools"); import forgegui; forgegui.call("generation_status", {...})
"""
import argparse
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

MCP_URL = "https://forgegui.com/mcp"
KEYS_FILE = os.environ.get("FORGEGUI_KEYS_FILE", "/mnt/project-files/secrets/forgegui-keys.json")
DEFAULT_COST = 1600  # credits per thumbnail / gui image as of 2026-10-31; learned per type from errors
NOW = lambda: dt.datetime.now(dt.timezone.utc)


# ---------------------------------------------------------------- key store
def key_id(key):
    """Short public id: the uuid part's first 8 chars (the key's secret half is never shown)."""
    parts = key.split("_")
    return parts[1][:8] if len(parts) > 2 else hashlib.sha256(key.encode()).hexdigest()[:8]


@contextlib.contextmanager
def store(write=True):
    os.makedirs(os.path.dirname(KEYS_FILE), exist_ok=True)
    lock = open(KEYS_FILE + ".lock", "a+")
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        data = json.load(open(KEYS_FILE)) if os.path.exists(KEYS_FILE) else {}
        data.setdefault("keys", [])
        data.setdefault("costs", {})
        data.setdefault("last_used", None)
        yield data
        if write:
            tmp = KEYS_FILE + ".tmp"
            json.dump(data, open(tmp, "w"), indent=1)
            os.chmod(tmp, 0o600)
            os.replace(tmp, KEYS_FILE)
    finally:
        fcntl.flock(lock, fcntl.LOCK_UN)
        lock.close()


def add_keys(keys):
    added = []
    with store() as d:
        have = {k["key"] for k in d["keys"]}
        for key in keys:
            key = key.strip()
            if key and key.startswith("fgmcp_") and key not in have:
                d["keys"].append({"key": key, "id": key_id(key), "state": "unknown", "balance": None,
                                  "balance_at": None, "refills_at": None, "daily_amount": None,
                                  "spent_since": 0, "uploads": {}, "note": ""})
                have.add(key)
                added.append(key_id(key))
    return added


def _parse_time(s):
    try:
        return dt.datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None
    except ValueError:
        return None


def estimate(k):
    if k["balance"] is None:
        return None
    return max(0, k["balance"] - k.get("spent_since", 0))


def refilled(k):
    t = _parse_time(k.get("refills_at"))
    return t is not None and t <= NOW()


# ---------------------------------------------------------------- MCP transport
def _rpc(key, method, params, id_=1, session=None):
    h = {"Authorization": "Bearer " + key, "Content-Type": "application/json",
         "Accept": "application/json, text/event-stream"}
    if session:
        h["Mcp-Session-Id"] = session
    body = {"jsonrpc": "2.0", "method": method, "params": params}
    if id_ is not None:
        body["id"] = id_
    r = urllib.request.urlopen(urllib.request.Request(MCP_URL, json.dumps(body).encode(), h), timeout=180)
    session = r.headers.get("Mcp-Session-Id") or session
    txt = r.read().decode()
    if "data:" in txt:
        txt = [line[5:] for line in txt.splitlines() if line.startswith("data:")][-1]
    return (json.loads(txt) if txt.strip() else None), session


_sessions = {}


def raw_call(key, tool, args):
    """One MCP tool call with one key. Returns (ok, payload dict)."""
    sess = _sessions.get(key)
    if key not in _sessions:
        _, sess = _rpc(key, "initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                                           "clientInfo": {"name": "forgegui-pool", "version": "1"}})
        try:
            _rpc(key, "notifications/initialized", {}, None, sess)
        except Exception:
            pass
        _sessions[key] = sess
    r, _ = _rpc(key, "tools/call", {"name": tool, "arguments": args}, 2, sess)
    if "error" in r and "result" not in r:
        return False, {"error": r["error"]}
    res = r["result"]
    sc = res.get("structuredContent")
    if sc is None:
        text = (res.get("content") or [{}])[0].get("text", "")
        try:
            sc = json.loads(text)
        except ValueError:
            sc = {"text": text}
    return not res.get("isError"), sc


def _is_insufficient(payload):
    s = json.dumps(payload)
    return "insufficient_credits" in s


def _record_empty(k, payload, tool_type):
    p = payload
    if isinstance(p.get("error"), str):
        try:
            p = json.loads(p["error"])
        except ValueError:
            pass
    df = p.get("daily_free") or {}
    k["state"] = "empty"
    k["note"] = ""
    k["balance"] = p.get("credits_available", 0)
    k["balance_at"] = NOW().isoformat()
    k["spent_since"] = 0
    k["refills_at"] = df.get("refills_at") or k.get("refills_at")
    k["daily_amount"] = df.get("daily_amount") or k.get("daily_amount")
    return p.get("credits_required")


PAID = {"generation_image", "generation_gui", "generation_model_3d", "generation_rig_3d", "generation_remesh_3d",
        "generation_animate_3d", "generation_sound_effect", "generation_music", "remove_background",
        "enhance_prompt", "drawing_reference", "auto_separate"}


def cost_of(d, tool, args):
    t = args.get("type", "")
    return d["costs"].get(f"{tool}:{t}", d["costs"].get(tool, DEFAULT_COST if tool in PAID else 0)) * int(args.get("count", 1) if tool == "generation_image" else 1)


def order(d, need):
    """Keys to try, best first."""
    def usable(k):
        if k["state"] == "invalid":
            return False
        if k["state"] == "empty" and not refilled(k):
            return need == 0
        e = estimate(k)
        return need == 0 or e is None or e >= need or refilled(k)
    ks = [k for k in d["keys"] if usable(k)]
    # least-spent first, so parallel jobs land on different accounts (credits are only charged
    # when a job finishes, so several jobs on one key can overdraw it)
    ks.sort(key=lambda k: (k.get("spent_since", 0) + k.get("inflight", 0), -(estimate(k) if estimate(k) is not None else 10_000)))
    return ks


def attempt(key, tool, args):
    """Run tool on one key and book-keep. Returns (status, payload); status is "ok", "error",
    "empty" (out of credits, recorded) or "invalid" (key rejected)."""
    try:
        ok, payload = raw_call(key, tool, args)
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            with store() as d:
                k = next(k for k in d["keys"] if k["key"] == key)
                k["state"], k["note"] = "invalid", f"HTTP {e.code}"
            return "invalid", {"http": e.code}
        raise
    with store() as d:
        k = next(k for k in d["keys"] if k["key"] == key)
        if _is_insufficient(payload):
            req = _record_empty(k, payload, args.get("type"))
            if req and tool in PAID:
                per = req // max(1, int(args.get("count", 1))) if tool == "generation_image" else req
                ck = f"{tool}:{args.get('type', '')}"
                d["costs"][ck] = max(per, d["costs"].get(ck, 0))  # submit price; jobs can bill more
            return "empty", payload
        d["last_used"] = k["id"]
        if ok and tool in PAID:
            if k["state"] != "ok" and refilled(k):
                k["balance"], k["spent_since"], k["refills_at"] = None, 0, None
            k["state"] = "ok"
            k["spent_since"] = k.get("spent_since", 0) + cost_of(d, tool, args)
        elif ok and k["state"] in ("unknown", "invalid"):
            k["state"] = "ok"
    return ("ok" if ok else "error"), payload


def call(tool, args, need=None):
    """Run a ForgeGUI tool on the first key with enough credits; fail over on insufficient_credits.
    Returns (key_id, payload). Raises RuntimeError when every key is out."""
    with store(write=False) as d:
        need = cost_of(d, tool, args) if need is None else need
        cands = [k["key"] for k in order(d, need)]
    errors = []
    for key in cands:
        status, payload = attempt(key, tool, args)
        if status in ("empty", "invalid"):
            errors.append(f"{key_id(key)}: {status}")
            continue
        return key_id(key), payload
    raise RuntimeError("No ForgeGUI key has enough credits. " + "; ".join(errors))


def probe(all_keys=False):
    """Free check of each key: a generation with a made-up reference id fails before any charge,
    but the credit check comes first, so it tells empty (with exact balance) from usable."""
    out = []
    with store(write=False) as d:
        keys = [k["key"] for k in d["keys"] if all_keys or k["state"] in ("unknown", "empty") or refilled(k)]
        cost = d["costs"].get("generation_image:thumbnail", DEFAULT_COST)
    for key in keys:
        args = {"request_id": f"probe-{int(time.time() * 1000)}-{key_id(key)}", "type": "thumbnail",
                "prompt": "balance probe", "reference_asset_ids": ["00000000-0000-4000-8000-000000000000"]}
        try:
            ok, payload = raw_call(key, "generation_image", args)
        except urllib.error.HTTPError as e:
            payload, ok = {"http": e.code}, False
        with store() as d:
            k = next(k for k in d["keys"] if k["key"] == key)
            if payload.get("http") in (401, 403):
                k["state"], k["note"] = "invalid", f"HTTP {payload['http']}"
            elif _is_insufficient(payload):
                _record_empty(k, payload, "thumbnail")
            else:
                if k["state"] == "empty":
                    k["balance"], k["spent_since"] = None, 0
                k["state"] = "ok"
                k["note"] = f"has >= {cost} credits (checked {NOW():%Y-%m-%d %H:%M}Z)"
            out.append((k["id"], k["state"], estimate(k), k.get("refills_at")))
    return out


# ---------------------------------------------------------------- helpers for images
def _upload(key, path):
    data = open(path, "rb").read()
    ct = {".png": "image/png", ".webp": "image/webp"}.get(os.path.splitext(path)[1].lower(), "image/jpeg")
    ok, a = raw_call(key, "image_upload_authorize", {"content_type": ct, "byte_size": len(data)})
    if not ok:
        raise RuntimeError(f"upload authorize failed: {a}")
    urllib.request.urlopen(urllib.request.Request(a["upload_url"], data, {"Content-Type": ct}, method="PUT"), timeout=120).read()
    ok, reg = raw_call(key, "image_upload_register", {"upload_id": a["upload_id"]})
    if not ok:
        raise RuntimeError(f"upload register failed: {reg}")
    return reg.get("asset_id") or reg.get("id")


def refs_for(key, files):
    ids = []
    for f in files:
        h = hashlib.sha256(open(f, "rb").read()).hexdigest()[:16]
        with store(write=False) as d:
            cached = next(k for k in d["keys"] if k["key"] == key).get("uploads", {}).get(h)
        if not cached:
            cached = _upload(key, f)
            with store() as d:
                next(k for k in d["keys"] if k["key"] == key).setdefault("uploads", {})[h] = cached
        ids.append(cached)
    return ids


def wait(job_id, kid, timeout=900):
    with store(write=False) as d:
        key = next(k["key"] for k in d["keys"] if k["id"] == kid)
    t0 = time.time()
    while True:
        ok, st = raw_call(key, "generation_status", {"job_id": job_id})
        if st.get("status") not in ("queued", "running", "pending", "processing"):
            return st
        if time.time() - t0 > timeout:
            return st
        time.sleep(6)


def image(out_dir, prompt, type_="thumbnail", refs=(), count=1, style=None, request_id=None, extra=None):
    """Generate images with automatic key choice. Returns list of saved file paths."""
    os.makedirs(out_dir, exist_ok=True)
    request_id = request_id or f"img-{int(time.time())}"
    with store(write=False) as d:
        need = d["costs"].get(f"generation_image:{type_}", DEFAULT_COST) * count
        keys = [k["key"] for k in order(d, need)]
    tried = []
    for key in keys:
        args = {"request_id": f"{request_id}-{key_id(key)}", "type": type_, "prompt": prompt, "count": count}
        if style:
            args["game_style"] = style
        if extra:
            args.update(extra)
        if refs:
            args["reference_asset_ids"] = refs_for(key, refs)  # uploads belong to one account
        status, r = attempt(key, "generation_image", args)
        tried.append(f"{key_id(key)}: {status}")
        if status in ("empty", "invalid"):
            continue
        if status == "error":
            raise RuntimeError(f"generation_image failed: {json.dumps(r)[:600]}")
        st = wait(r["job_id"], key_id(key)) if r.get("status") in ("queued", "running") else r
        if st.get("status") != "succeeded" and "out of ForgeGUI credits" in str(st.get("error")):
            with store() as d:  # the credit check passed at submit, but the account ran dry before the job ended
                k = next(k for k in d["keys"] if k["key"] == key)
                k["state"], k["balance"], k["balance_at"], k["spent_since"] = "empty", 0, NOW().isoformat(), 0
                k["note"] = "ran out mid-job"
            tried[-1] = f"{key_id(key)}: ran out mid-job"
            continue
        if st.get("status") != "succeeded":
            raise RuntimeError(f"job {r.get('job_id')} {st.get('status')}: {st.get('error')}")
        paths = []
        for i, a in enumerate((st.get("result") or {}).get("artifacts", [])):
            p = os.path.join(out_dir, f"{request_id}_{i}.png")
            urllib.request.urlretrieve(a["url"], p)
            paths.append(p)
        return paths
    raise RuntimeError(f"no key could run the job: {"; ".join(tried)}")


# ---------------------------------------------------------------- CLI
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("add"); a.add_argument("keys", nargs="+")
    sub.add_parser("status")
    p = sub.add_parser("probe"); p.add_argument("--all", action="store_true")
    k = sub.add_parser("pick"); k.add_argument("--need", type=int, default=DEFAULT_COST)
    c = sub.add_parser("call"); c.add_argument("tool"); c.add_argument("args")
    i = sub.add_parser("image"); i.add_argument("out"); i.add_argument("--prompt", required=True)
    i.add_argument("--type", default="thumbnail"); i.add_argument("--ref", action="append", default=[])
    i.add_argument("--count", type=int, default=1); i.add_argument("--style"); i.add_argument("--id")
    o = ap.parse_args()
    if o.cmd == "add":
        print("added:", ", ".join(add_keys(o.keys)) or "nothing new")
    elif o.cmd == "status":
        with store(write=False) as d:
            print(f"{'key':10} {'state':8} {'credits':>8}  refills_at                 note")
            for k in d["keys"]:
                e = estimate(k)
                print(f"{k['id']:10} {k['state']:8} {('?' if e is None else e):>8}  {str(k.get('refills_at') or ''):26} {k.get('note', '')}")
            print("costs:", d["costs"] or f"default {DEFAULT_COST}", " last used:", d["last_used"])
    elif o.cmd == "probe":
        for row in probe(o.all):
            print(*row)
    elif o.cmd == "pick":
        with store(write=False) as d:
            ks = order(d, o.need)
            print(ks[0]["id"] if ks else "none")
    elif o.cmd == "call":
        kid, r = call(o.tool, json.loads(o.args))
        print(f"[key {kid}]")
        print(json.dumps(r, indent=1)[:8000])
    elif o.cmd == "image":
        for p in image(o.out, o.prompt, o.type, o.ref, o.count, o.style, o.id):
            print(p)


if __name__ == "__main__":
    main()
