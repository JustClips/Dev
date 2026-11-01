# Pack-style icon generator (ForgeUI key pool). Usage: python3 gen.py TAG [names...]; prompts in prompts.json, outputs in raw/, then proc.py.
import sys, os, json, urllib.request, concurrent.futures as cf
sys.path.insert(0, "/home/user/dev/tools")
import forgegui
HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw"); os.makedirs(RAW, exist_ok=True)
REF = os.path.join(HERE, "ref.png")
STYLE = ("Game UI icon. Match the art style of the reference image exactly: chunky glossy cartoon icon, very thick dark navy-black outline "
         "around the whole silhouette, bright saturated colours with soft gradient shading, a few sharp white glint highlights, "
         "slightly tilted 3/4 view, simple bold shapes. Draw ONLY the object described below (not the sword, coin, bomb or axe from the reference). "
         "One single object, centred, filling most of the frame, on a plain pure white background. No text, no letters, no frame, no tile behind it.")
ICONS = json.load(open(os.path.join(HERE, "prompts.json")))
TAG = sys.argv[1]
only = sys.argv[2:] or list(ICONS)

def one(name):
    path = os.path.join(RAW, name + ".png")
    if os.path.exists(path):
        return name, "cached"
    prompt = f"{STYLE} The object: {ICONS[name]}."
    with forgegui.store(write=False) as d:
        keys = [k["key"] for k in forgegui.order(d, 1600)]
    for key in keys[:6]:
        args = {"request_id": f"pack-{name.lower()}-{TAG}-{forgegui.key_id(key)}", "type": "gui_icon", "prompt": prompt, "count": 1,
                "reference_asset_ids": forgegui.refs_for(key, [REF])}
        status, r = forgegui.attempt(key, "generation_gui", args)
        if status in ("empty", "invalid"):
            continue
        if status == "error":
            return name, f"error {json.dumps(r)[:200]}"
        st = r
        if r.get("status") in ("queued", "running", "pending", "processing"):
            import time
            for _ in range(8):
                try:
                    st = forgegui.wait(r["job_id"], forgegui.key_id(key)); break
                except Exception as e:
                    time.sleep(20)
        if st.get("status") != "succeeded":
            if "credits" in str(st.get("error")):
                continue
            return name, f"{st.get('status')}: {str(st.get('error'))[:200]}"
        arts = (st.get("result") or {}).get("artifacts", [])
        if not arts:
            return name, "no artifact"
        urllib.request.urlretrieve(arts[0]["url"], path)
        return name, "ok"
    return name, "no key"

with cf.ThreadPoolExecutor(3) as ex:
    for name, msg in ex.map(one, only):
        print(name, msg, flush=True)
