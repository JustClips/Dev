import json, os, subprocess, time
key = os.environ["ROBLOXAPIKEY"]; U="10773346969"; API="https://apis.roblox.com"
def curl(method, path, form=None):
    cmd=["curl","-sS","-X",method,"-H","x-api-key: "+key,"-w","\n%{http_code}",API+path]
    for k,v in (form or {}).items(): cmd += ["-F", f"{k}={v}"]
    out=subprocess.run(cmd,capture_output=True,text=True).stdout; body,_,code=out.rpartition("\n"); return code, body
plan=json.load(open("plan2.json")); bad=[]
for k,(pid,name,kind) in plan.items():
    path = f"/developer-products/v2/universes/{U}/developer-products/{pid}" if kind=="product" else f"/game-passes/v1/universes/{U}/game-passes/{pid}"
    for attempt in range(4):
        c,b=curl("PATCH", path, {"imageFile": f"@out/{k}.png;type=image/png"})
        if c.startswith("2"): break
        time.sleep(3*(attempt+1))
    if not c.startswith("2"): bad.append((k,c,b[:120]))
    time.sleep(0.4)
print("done", len(plan), "failed", bad)
