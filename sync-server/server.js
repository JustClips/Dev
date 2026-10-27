// LiveSync server: mirrors a GitHub repo and serves its Rojo-style tree to the
// LiveSync Studio plugin. The plugin long-polls /api/state and applies changes.
//
// Env:
//   SYNC_KEY       required. Shared key the Studio plugin sends as X-Sync-Key.
//   REPO_URL       git URL of the game repo (default: megafartCc/gamedev).
//   GITHUB_TOKEN   read token for a private repo (fine-grained, Contents: read).
//   BRANCH         default "main".
//   POLL_SECONDS   how often to check GitHub for new commits (default 3).
//   WEBHOOK_SECRET optional. If set, POST /webhook (GitHub push webhook) triggers an instant fetch.
//   PROJECT_FILE   default "default.project.json".
//   PORT           set by Railway.

"use strict";
const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { execFile } = require("child_process");

const SYNC_KEY = process.env.SYNC_KEY || "";
const REPO_URL = process.env.REPO_URL || "https://github.com/megafartCc/GAMEDEV.git";
const GITHUB_TOKEN = process.env.GITHUB_TOKEN || "";
const BRANCH = process.env.BRANCH || "main";
const POLL_SECONDS = Number(process.env.POLL_SECONDS || 3);
const WEBHOOK_SECRET = process.env.WEBHOOK_SECRET || "";
const PROJECT_FILE = process.env.PROJECT_FILE || "default.project.json";
const PORT = Number(process.env.PORT || 34873);
const WORKDIR = process.env.WORKDIR || path.join(require("os").tmpdir(), "livesync-repo");
// Set LOCAL_DIR to serve a local folder instead of cloning (for testing).
const LOCAL_DIR = process.env.LOCAL_DIR || "";
const STARTED_AT = new Date().toISOString();

if (!SYNC_KEY) {
  console.error("SYNC_KEY is not set; refusing to start (the API would be open to anyone).");
  process.exit(1);
}

function authedUrl() {
  if (!GITHUB_TOKEN) return REPO_URL;
  const u = new URL(REPO_URL);
  u.username = "x-access-token";
  u.password = GITHUB_TOKEN;
  return u.toString();
}

function git(args, cwd) {
  return new Promise((resolve, reject) => {
    execFile("git", args, { cwd, maxBuffer: 64 * 1024 * 1024 }, (err, stdout, stderr) => {
      if (err) {
        const msg = String(stderr || err.message).split(GITHUB_TOKEN || "\u0000").join("***");
        reject(new Error(msg.trim()));
      } else resolve(stdout.trim());
    });
  });
}

// ---------- Rojo-style tree builder ----------

const SCRIPT_RE = /^(.*?)(\.server|\.client)?\.(lua|luau)$/;

function classForScript(kind) {
  if (kind === ".server") return "Script";
  if (kind === ".client") return "LocalScript";
  return "ModuleScript";
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

// Turns a file or folder on disk into nodes. `segs` is the instance path.
function buildFromPath(abs, segs, out) {
  let st;
  try {
    st = fs.statSync(abs);
  } catch {
    return;
  }
  if (st.isFile()) {
    const m = path.basename(abs).match(SCRIPT_RE);
    if (m) {
      out.push({ path: segs, className: classForScript(m[2]), source: fs.readFileSync(abs, "utf8") });
    } else if (abs.endsWith(".txt")) {
      out.push({ path: segs, className: "StringValue", value: fs.readFileSync(abs, "utf8") });
    }
    return;
  }
  if (!st.isDirectory()) return;

  const entries = fs.readdirSync(abs).filter((n) => !n.startsWith(".")).sort();
  let node = { path: segs, className: "Folder" };
  for (const n of entries) {
    const m = n.match(/^init(\.server|\.client)?\.(lua|luau)$/);
    if (m) {
      node = { path: segs, className: classForScript(m[1]), source: fs.readFileSync(path.join(abs, n), "utf8") };
      break;
    }
  }
  const meta = readJson(path.join(abs, "init.meta.json"));
  if (meta && meta.className && node.className === "Folder") node.className = meta.className;
  out.push(node);

  for (const n of entries) {
    if (/^init(\.server|\.client)?\.(lua|luau)$/.test(n) || n === "init.meta.json") continue;
    if (n.endsWith(".meta.json")) continue;
    const child = path.join(abs, n);
    let name = n;
    if (fs.statSync(child).isFile()) {
      const m = n.match(SCRIPT_RE);
      if (m) name = m[1];
      else if (n.endsWith(".txt")) name = n.slice(0, -4);
      else continue;
    }
    buildFromPath(child, segs.concat(name), out);
  }
}

// Walks a project.json tree node.
function buildFromProject(root, tree, segs, out) {
  if (segs.length > 0) {
    if (tree.$path) {
      buildFromPath(path.join(root, tree.$path), segs, out);
    } else {
      out.push({ path: segs, className: tree.$className || (segs.length === 1 ? "Service" : "Folder"), container: true });
    }
  }
  for (const [key, child] of Object.entries(tree)) {
    if (key.startsWith("$") || typeof child !== "object" || child === null) continue;
    buildFromProject(root, child, segs.concat(key), out);
  }
}

function buildSnapshot(root) {
  const project = readJson(path.join(root, PROJECT_FILE));
  if (!project || !project.tree) throw new Error(`${PROJECT_FILE} missing or has no "tree"`);
  const nodes = [];
  buildFromProject(root, project.tree, [], nodes);
  return nodes;
}

// ---------- state + polling ----------

// version is a content hash, so it stays stable across restarts/redeploys and a
// plugin can never miss an update because a counter reset.
let state = { version: "", commit: null, hash: null, nodes: [], error: null, updatedAt: null };
let waiters = [];

function publish(commit, nodes) {
  const hash = crypto.createHash("sha1").update(JSON.stringify(nodes)).digest("hex");
  if (hash === state.hash) {
    state.commit = commit;
    return;
  }
  state = { version: hash.slice(0, 12), commit, hash, nodes, error: null, updatedAt: new Date().toISOString() };
  console.log(`v${state.version} commit=${commit} nodes=${nodes.length}`);
  const w = waiters;
  waiters = [];
  for (const fn of w) fn();
}

let syncing = false;
let lastRemote = null;

async function syncOnce() {
  if (syncing) return;
  syncing = true;
  try {
    if (LOCAL_DIR) {
      publish("local", buildSnapshot(LOCAL_DIR));
      return;
    }
    if (!fs.existsSync(path.join(WORKDIR, ".git"))) {
      fs.rmSync(WORKDIR, { recursive: true, force: true });
      await git(["clone", "--depth", "1", "--branch", BRANCH, authedUrl(), WORKDIR]);
      lastRemote = null;
    }
    const remote = (await git(["ls-remote", authedUrl(), `refs/heads/${BRANCH}`], WORKDIR)).split(/\s+/)[0];
    if (remote && remote === lastRemote) return;
    await git(["fetch", "--depth", "1", authedUrl(), BRANCH], WORKDIR);
    await git(["reset", "--hard", "FETCH_HEAD"], WORKDIR);
    const commit = await git(["rev-parse", "HEAD"], WORKDIR);
    publish(commit, buildSnapshot(WORKDIR));
    lastRemote = remote;
  } catch (e) {
    if (state.error !== e.message) console.error("sync error:", e.message);
    state.error = e.message;
  } finally {
    syncing = false;
  }
}

// ---------- HTTP ----------

function send(res, code, body) {
  const data = JSON.stringify(body);
  res.writeHead(code, { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(data) });
  res.end(data);
}

function keyOk(req) {
  const got = Buffer.from(String(req.headers["x-sync-key"] || ""));
  const want = Buffer.from(SYNC_KEY);
  return got.length === want.length && crypto.timingSafeEqual(got, want);
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://x");

  if (url.pathname === "/" || url.pathname === "/healthz") {
    return send(res, 200, { ok: true, name: "livesync", startedAt: STARTED_AT, version: state.version, commit: state.commit, error: state.error });
  }

  if (url.pathname === "/webhook" && req.method === "POST") {
    let body = [];
    req.on("data", (c) => body.push(c));
    req.on("end", () => {
      body = Buffer.concat(body);
      if (WEBHOOK_SECRET) {
        const sig = String(req.headers["x-hub-signature-256"] || "");
        const want = "sha256=" + crypto.createHmac("sha256", WEBHOOK_SECRET).update(body).digest("hex");
        if (sig.length !== want.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(want))) {
          return send(res, 401, { error: "bad signature" });
        }
      }
      lastRemote = null;
      syncOnce();
      send(res, 200, { ok: true });
    });
    return;
  }

  if (url.pathname === "/api/state" && req.method === "GET") {
    if (!keyOk(req)) {
      console.log(`401 wrong sync key from ${req.headers["x-forwarded-for"] || req.socket.remoteAddress}`);
      return send(res, 401, { error: "bad or missing X-Sync-Key" });
    }
    if (url.searchParams.get("since") !== state.version) {
      console.log(`plugin sync: since=${url.searchParams.get("since") || "(none)"} -> ${state.version}`);
    }
    const since = String(url.searchParams.get("since") || "");
    const wait = Math.min(Number(url.searchParams.get("wait") || 0), 25);
    const reply = () => {
      if (since === state.version) {
        send(res, 200, { version: state.version, commit: state.commit, unchanged: true, error: state.error });
      } else {
        send(res, 200, { version: state.version, commit: state.commit, nodes: state.nodes, error: state.error });
      }
    };
    if (since !== state.version || wait <= 0 || !state.version) return reply();
    let done = false;
    const fire = () => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      reply();
    };
    const timer = setTimeout(fire, wait * 1000);
    waiters.push(fire);
    req.on("close", () => {
      done = true;
      clearTimeout(timer);
    });
    return;
  }

  send(res, 404, { error: "not found" });
});

server.listen(PORT, () => console.log(`livesync listening on :${PORT}, repo=${LOCAL_DIR || REPO_URL} branch=${BRANCH}`));
syncOnce();
setInterval(syncOnce, POLL_SECONDS * 1000);
