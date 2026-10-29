// LiveSync server: mirrors a GitHub repo and serves its Rojo-style tree to the
// LiveSync Studio plugin. The plugin long-polls /api/state and applies changes.
//
// Env:
//   SYNC_KEY       required. Shared key the Studio plugin sends as X-Sync-Key.
//   REPO_URL       git URL of the game repo (default: JustClips/Dev).
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
const REPO_URL = process.env.REPO_URL || "https://github.com/JustClips/Dev.git";
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
const INIT_RE = /^init(\.server|\.client)?\.(lua|luau)$/;
const HISTORY_DEPTH = Number(process.env.HISTORY_DEPTH || 30);

function classForScript(kind) {
  if (kind === ".server") return "Script";
  if (kind === ".client") return "LocalScript";
  return "ModuleScript";
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (e) {
    if (fs.existsSync(file)) warnings.push(`${path.relative(currentRoot, file)}: ${e.message}`);
    return null;
  }
}

// Reads a key in either camelCase (Rojo 7) or PascalCase.
function pick(obj, key) {
  if (!obj) return undefined;
  if (obj[key] !== undefined) return obj[key];
  const pascal = key[0].toUpperCase() + key.slice(1);
  return obj[pascal];
}

// Applies className / properties / attributes / tags from a meta-like object.
function applyMeta(node, meta) {
  if (!meta) return node;
  const className = pick(meta, "className");
  if (className && (node.className === "Folder" || node.container)) node.className = className;
  const props = Object.assign({}, pick(meta, "properties") || {});
  const attrs = Object.assign({}, pick(meta, "attributes") || {}, props.Attributes || {});
  delete props.Attributes;
  let tags = pick(meta, "tags") || props.Tags;
  delete props.Tags;
  if (Object.keys(props).length) node.properties = Object.assign(node.properties || {}, props);
  if (Object.keys(attrs).length) node.attributes = Object.assign(node.attributes || {}, attrs);
  if (Array.isArray(tags)) node.tags = tags;
  return node;
}

// A .model.json tree: { className, properties, attributes, tags, children: [{ name, ... }] }
function buildFromModel(model, segs, out) {
  const node = { path: segs, className: pick(model, "className") || "Folder" };
  applyMeta(node, Object.assign({}, model, { className: undefined, ClassName: undefined }));
  out.push(node);
  const children = pick(model, "children") || [];
  const used = new Set();
  for (const child of children) {
    let name = pick(child, "name") || pick(child, "className") || "Instance";
    // Two siblings with the same name would collide on path; number the extras.
    let unique = name, i = 2;
    while (used.has(unique)) unique = `${name} (${i++})`;
    if (unique !== name) warnings.push(`${segs.join("/")}: duplicate child name "${name}", synced as "${unique}"`);
    used.add(unique);
    buildFromModel(child, segs.concat(unique), out);
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
  const base = path.basename(abs);
  if (st.isFile()) {
    const dir = path.dirname(abs);
    const m = base.match(SCRIPT_RE);
    if (m) {
      const node = { path: segs, className: classForScript(m[2]), source: fs.readFileSync(abs, "utf8") };
      out.push(applyMeta(node, readJson(path.join(dir, `${m[1]}.meta.json`))));
    } else if (base.endsWith(".model.json")) {
      const model = readJson(abs);
      if (model) buildFromModel(model, segs, out);
    } else if (base.endsWith(".txt")) {
      const stem = base.slice(0, -4);
      const node = { path: segs, className: "StringValue", value: fs.readFileSync(abs, "utf8") };
      out.push(applyMeta(node, readJson(path.join(dir, `${stem}.meta.json`))));
    }
    return;
  }
  if (!st.isDirectory()) return;

  const entries = fs.readdirSync(abs).filter((n) => !n.startsWith(".")).sort();
  let node = { path: segs, className: "Folder" };
  for (const n of entries) {
    const m = n.match(INIT_RE);
    if (m) {
      node = { path: segs, className: classForScript(m[1]), source: fs.readFileSync(path.join(abs, n), "utf8") };
      break;
    }
  }
  applyMeta(node, readJson(path.join(abs, "init.meta.json")));
  out.push(node);

  for (const n of entries) {
    if (INIT_RE.test(n) || n.endsWith(".meta.json")) continue;
    const child = path.join(abs, n);
    let name = n;
    if (fs.statSync(child).isFile()) {
      const m = n.match(SCRIPT_RE);
      if (m) name = m[1];
      else if (n.endsWith(".model.json")) name = n.slice(0, -".model.json".length);
      else if (n.endsWith(".txt")) name = n.slice(0, -4);
      else continue;
    }
    buildFromPath(child, segs.concat(name), out);
  }
}

// Walks a project.json tree node ($className, $path, $properties, $attributes).
function buildFromProject(root, tree, segs, out) {
  if (segs.length > 0) {
    const meta = { className: tree.$className, properties: tree.$properties, attributes: tree.$attributes, tags: tree.$tags };
    if (tree.$path) {
      const start = out.length;
      buildFromPath(path.join(root, tree.$path), segs, out);
      if (out.length > start) applyMeta(out[start], meta);
    } else {
      out.push(applyMeta({ path: segs, className: tree.$className || (segs.length === 1 ? "Service" : "Folder"), container: true }, meta));
    }
  }
  for (const [key, child] of Object.entries(tree)) {
    if (key.startsWith("$") || typeof child !== "object" || child === null) continue;
    buildFromProject(root, child, segs.concat(key), out);
  }
}

let warnings = [];
let currentRoot = "";

function buildSnapshot(root) {
  warnings = [];
  currentRoot = root;
  const project = readJson(path.join(root, PROJECT_FILE));
  if (!project || !project.tree) throw new Error(`${PROJECT_FILE} missing or has no "tree"`);
  const nodes = [];
  buildFromProject(root, project.tree, [], nodes);
  return { nodes, warnings };
}

// Recent commits with message, author, time and changed files.
async function readHistory(cwd) {
  const SEP = "\u001e";
  const raw = await git(["log", `-n${HISTORY_DEPTH}`, "--name-status", `--format=${SEP}%H%x1f%an%x1f%aI%x1f%B%x1f`], cwd);
  const out = [];
  for (const chunk of raw.split(SEP)) {
    if (!chunk.trim()) continue;
    const [sha, author, date, message, rest] = chunk.split("\u001f");
    const files = [];
    for (const line of (rest || "").split("\n")) {
      const parts = line.trim().split("\t");
      if (parts.length < 2) continue;
      files.push({ status: parts[0][0], path: parts[parts.length - 1] });
    }
    out.push({ sha, author, date, message: (message || "").trim(), files });
  }
  return out;
}

// ---------- state + polling ----------

// version is a content hash, so it stays stable across restarts/redeploys and a
// plugin can never miss an update because a counter reset.
let state = { version: "", commit: null, hash: null, nodes: [], history: [], warnings: [], error: null, updatedAt: null };
let waiters = [];

function publish(commit, snap, history) {
  const hash = crypto.createHash("sha1").update(commit + JSON.stringify(snap.nodes)).digest("hex");
  if (hash === state.hash) return;
  state = {
    version: hash.slice(0, 12), commit, hash, nodes: snap.nodes, history, warnings: snap.warnings,
    error: null, updatedAt: new Date().toISOString(),
  };
  console.log(`v${state.version} commit=${commit.slice(0, 7)} nodes=${snap.nodes.length}` + (snap.warnings.length ? ` warnings=${snap.warnings.length}` : ""));
  for (const w of snap.warnings) console.log("  warning:", w);
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
      let history = [];
      try { history = await readHistory(LOCAL_DIR); } catch {}
      publish("local", buildSnapshot(LOCAL_DIR), history);
      return;
    }
    if (!fs.existsSync(path.join(WORKDIR, ".git"))) {
      fs.rmSync(WORKDIR, { recursive: true, force: true });
      await git(["clone", "--depth", String(HISTORY_DEPTH), "--branch", BRANCH, authedUrl(), WORKDIR]);
      lastRemote = null;
    }
    const remote = (await git(["ls-remote", authedUrl(), `refs/heads/${BRANCH}`], WORKDIR)).split(/\s+/)[0];
    if (remote && remote === lastRemote) return;
    await git(["fetch", "--depth", String(HISTORY_DEPTH), authedUrl(), BRANCH], WORKDIR);
    await git(["reset", "--hard", "FETCH_HEAD"], WORKDIR);
    const commit = await git(["rev-parse", "HEAD"], WORKDIR);
    publish(commit, buildSnapshot(WORKDIR), await readHistory(WORKDIR));
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
        send(res, 200, { version: state.version, commit: state.commit, nodes: state.nodes, history: state.history, warnings: state.warnings, error: state.error });
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
