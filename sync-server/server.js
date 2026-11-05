// LiveSync server: mirrors GitHub repos and serves their Rojo-style trees to the
// LiveSync Studio plugin. The plugin long-polls /api/state and applies changes.
//
// One server can sync many games: the plugin says which repo and branch it wants
// (?repo=owner/name&branch=main). Each repo+branch gets its own mirror, made on
// first use and dropped after it has been idle for a while.
//
// Env:
//   SYNC_KEY       required. Shared key the Studio plugin sends as X-Sync-Key.
//   REPO_URL       default repo, used when the plugin sends no repo (default: JustClips/Dev).
//   BRANCH         default branch for REPO_URL (default "main").
//   GITHUB_TOKEN   read token for private repos (fine-grained, Contents: read). Used for every github.com repo.
//   ALLOWED_REPOS  optional comma list ("owner/name" or "owner/*"). If set, other repos are refused.
//   MAX_REPOS      most mirrors kept at once (default 12).
//   IDLE_MINUTES   a mirror nobody has asked for in this long stops polling and is dropped (default 30).
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

// ---------- config ----------

const SYNC_KEY = process.env.SYNC_KEY || "";
const REPO_URL = process.env.REPO_URL || "https://github.com/JustClips/Dev.git";
const GITHUB_TOKEN = process.env.GITHUB_TOKEN || "";
const BRANCH = process.env.BRANCH || "main";
const POLL_SECONDS = Number(process.env.POLL_SECONDS || 3);
const WEBHOOK_SECRET = process.env.WEBHOOK_SECRET || "";
const PROJECT_FILE = process.env.PROJECT_FILE || "default.project.json";
const PORT = Number(process.env.PORT || 34873);
const MAX_REPOS = Number(process.env.MAX_REPOS || 12);
const IDLE_MS = Number(process.env.IDLE_MINUTES || 30) * 60 * 1000;
const ALLOWED_REPOS = (process.env.ALLOWED_REPOS || "").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
const WORKROOT = process.env.WORKDIR || path.join(require("os").tmpdir(), "livesync-repos");
// Set LOCAL_DIR to serve a local folder as the default repo instead of cloning (for testing).
const LOCAL_DIR = process.env.LOCAL_DIR || "";
const STARTED_AT = new Date().toISOString();

if (!SYNC_KEY) {
  console.error("SYNC_KEY is not set; refusing to start (the API would be open to anyone).");
  process.exit(1);
}

// "owner/name", "github.com/owner/name", "https://github.com/owner/name(.git)(/tree/branch)" -> "owner/name"
function parseRepo(input) {
  let s = String(input || "").trim();
  s = s.replace(/^git@github\.com:/i, "").replace(/^(https?:\/\/)?(www\.)?github\.com\//i, "");
  s = s.replace(/\/tree\/.*$/, "").replace(/\.git$/i, "").replace(/\/+$/, "");
  const m = s.match(/^([A-Za-z0-9][A-Za-z0-9-]{0,38})\/([A-Za-z0-9._-]{1,100})$/);
  if (!m || m[2] === "." || m[2] === "..") return null;
  return `${m[1]}/${m[2]}`;
}

function validBranch(b) {
  return typeof b === "string" && b.length > 0 && b.length <= 200 && /^[A-Za-z0-9._\/-]+$/.test(b) &&
    !b.startsWith("-") && !b.startsWith("/") && !b.includes("..") && !b.endsWith(".lock");
}

function repoAllowed(repo) {
  if (!ALLOWED_REPOS.length) return true;
  const r = repo.toLowerCase();
  const owner = r.split("/")[0];
  return ALLOWED_REPOS.includes(r) || ALLOWED_REPOS.includes(`${owner}/*`);
}

const DEFAULT_REPO = parseRepo(REPO_URL) || REPO_URL;

function gitUrl(repo) {
  const plain = repo === DEFAULT_REPO && !parseRepo(REPO_URL) ? REPO_URL : `https://github.com/${repo}.git`;
  if (!GITHUB_TOKEN) return plain;
  const u = new URL(plain);
  if (u.hostname !== "github.com") return plain;
  u.username = "x-access-token";
  u.password = GITHUB_TOKEN;
  return u.toString();
}

function git(args, cwd) {
  return new Promise((resolve, reject) => {
    execFile("git", args, { cwd, maxBuffer: 64 * 1024 * 1024, env: Object.assign({}, process.env, { GIT_TERMINAL_PROMPT: "0" }) }, (err, stdout, stderr) => {
      if (err) {
        let msg = String(stderr || err.message).split(GITHUB_TOKEN || "\u0000").join("***");
        // git asks for a password when a repo is private or missing; say that plainly.
        if (/could not read Username|terminal prompts disabled|Repository not found|Authentication failed/i.test(msg)) {
          msg = GITHUB_TOKEN
            ? "Repository not found, or the server's GITHUB_TOKEN can't read it."
            : "Repository not found, or it's private (the server has no GITHUB_TOKEN).";
        } else if (/Remote branch .* not found|couldn't find remote ref/i.test(msg)) {
          msg = "Branch not found.";
        }
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

function buildSnapshot(root, projectFile) {
  warnings = [];
  currentRoot = root;
  const project = readJson(path.join(root, projectFile));
  if (!project || !project.tree) throw new Error(`${projectFile} missing or has no "tree"`);
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

// ---------- mirrors (one per repo + branch) ----------

class Mirror {
  constructor(repo, branch, localDir) {
    this.repo = repo;
    this.branch = branch;
    this.key = `${repo.toLowerCase()}@${branch}`;
    this.localDir = localDir || "";
    this.workdir = path.join(WORKROOT, this.key.replace(/[^A-Za-z0-9._-]/g, "_"));
    // version is a content hash, so it stays stable across restarts/redeploys and a
    // plugin can never miss an update because a counter reset.
    this.state = { version: "", commit: null, hash: null, nodes: [], history: [], warnings: [], error: null, updatedAt: null };
    this.waiters = [];
    this.syncing = false;
    this.lastRemote = null;
    this.lastUsed = Date.now();
    this.retryAt = 0;
    this.firstSync = this.syncOnce();
  }

  notify() {
    const w = this.waiters;
    this.waiters = [];
    for (const fn of w) fn();
  }

  publish(commit, snap, history) {
    const hash = crypto.createHash("sha1").update(commit + JSON.stringify(snap.nodes)).digest("hex");
    if (hash === this.state.hash) {
      if (this.state.error) {
        this.state.error = null;
        this.notify();
      }
      return;
    }
    this.state = {
      version: hash.slice(0, 12), commit, hash, nodes: snap.nodes, history, warnings: snap.warnings,
      error: null, updatedAt: new Date().toISOString(),
    };
    console.log(`[${this.key}] v${this.state.version} commit=${commit.slice(0, 7)} nodes=${snap.nodes.length}` + (snap.warnings.length ? ` warnings=${snap.warnings.length}` : ""));
    for (const w of snap.warnings) console.log("  warning:", w);
    this.notify();
  }

  async syncOnce(force) {
    if (this.syncing) return;
    // A repo/branch that has never loaded (typo, private, deleted) is retried slowly.
    if (!force && !this.state.version && this.state.error && Date.now() < this.retryAt) return;
    this.syncing = true;
    try {
      if (this.localDir) {
        let history = [];
        try { history = await readHistory(this.localDir); } catch {}
        this.publish("local", buildSnapshot(this.localDir, PROJECT_FILE), history);
        return;
      }
      const url = gitUrl(this.repo);
      if (!fs.existsSync(path.join(this.workdir, ".git"))) {
        fs.rmSync(this.workdir, { recursive: true, force: true });
        fs.mkdirSync(WORKROOT, { recursive: true });
        await git(["clone", "--depth", String(HISTORY_DEPTH), "--branch", this.branch, "--", url, this.workdir], WORKROOT);
        this.lastRemote = null;
      }
      const remote = (await git(["ls-remote", url, `refs/heads/${this.branch}`], this.workdir)).split(/\s+/)[0];
      if (!remote) throw new Error("Branch not found.");
      if (remote === this.lastRemote) return;
      await git(["fetch", "--depth", String(HISTORY_DEPTH), url, this.branch], this.workdir);
      await git(["reset", "--hard", "FETCH_HEAD"], this.workdir);
      const commit = await git(["rev-parse", "HEAD"], this.workdir);
      this.publish(commit, buildSnapshot(this.workdir, PROJECT_FILE), await readHistory(this.workdir));
      this.lastRemote = remote;
    } catch (e) {
      if (e.message === "Branch not found." && !this.state.version) {
        const heads = await git(["ls-remote", "--heads", gitUrl(this.repo)], WORKROOT).catch(() => "x");
        if (!heads) e.message = "This repo is empty. Push a first commit with default.project.json and src/.";
      }
      if (this.state.error !== e.message) {
        console.error(`[${this.key}] sync error:`, e.message);
        this.state.error = e.message;
        this.notify();
      }
      this.retryAt = Date.now() + 30000;
    } finally {
      this.syncing = false;
    }
  }

  summary() {
    return { repo: this.repo, branch: this.branch, version: this.state.version, commit: this.state.commit, error: this.state.error, lastUsed: new Date(this.lastUsed).toISOString() };
  }

  drop() {
    this.notify();
    fs.rm(this.workdir, { recursive: true, force: true }, () => {});
  }
}

const mirrors = new Map();
const defaultBranch = BRANCH;

function mirrorFor(repo, branch) {
  const key = `${repo.toLowerCase()}@${branch}`;
  let m = mirrors.get(key);
  if (m) {
    m.lastUsed = Date.now();
    return m;
  }
  if (mirrors.size >= MAX_REPOS) {
    // Make room by dropping the least recently used mirror (never the default one).
    let oldest = null;
    for (const x of mirrors.values()) {
      if (x.key === defaultKey) continue;
      if (!oldest || x.lastUsed < oldest.lastUsed) oldest = x;
    }
    if (oldest) {
      console.log(`[${oldest.key}] dropped (too many repos)`);
      mirrors.delete(oldest.key);
      oldest.drop();
    }
  }
  m = new Mirror(repo, branch, repo === DEFAULT_REPO && branch === defaultBranch ? LOCAL_DIR : "");
  mirrors.set(key, m);
  console.log(`[${key}] mirror created`);
  return m;
}

const defaultKey = `${DEFAULT_REPO.toLowerCase()}@${defaultBranch}`;

function pollAll() {
  const now = Date.now();
  for (const m of [...mirrors.values()]) {
    if (m.key !== defaultKey && now - m.lastUsed > IDLE_MS && m.waiters.length === 0) {
      console.log(`[${m.key}] dropped (idle)`);
      mirrors.delete(m.key);
      m.drop();
      continue;
    }
    m.syncOnce();
  }
}

// Branches of a repo plus its default branch, straight from GitHub.
async function listBranches(repo) {
  const url = gitUrl(repo);
  const [heads, head] = await Promise.all([
    git(["ls-remote", "--heads", url], WORKROOT),
    git(["ls-remote", "--symref", url, "HEAD"], WORKROOT).catch(() => ""),
  ]);
  const branches = heads.split("\n").map((l) => (l.split("\t")[1] || "").replace(/^refs\/heads\//, "")).filter(Boolean);
  const m = head.match(/^ref: refs\/heads\/(\S+)\s+HEAD/m);
  const def = m ? m[1] : branches.includes("main") ? "main" : branches[0] || null;
  branches.sort((a, b) => (a === def ? -1 : b === def ? 1 : a.localeCompare(b)));
  return { repo, defaultBranch: def, branches };
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

// Default branch of each repo, looked up once (for requests that name no branch).
const headCache = new Map();
async function repoDefaultBranch(repo) {
  if (repo === DEFAULT_REPO) return defaultBranch;
  const key = repo.toLowerCase();
  if (!headCache.has(key)) {
    fs.mkdirSync(WORKROOT, { recursive: true });
    const head = await git(["ls-remote", "--symref", gitUrl(repo), "HEAD"], WORKROOT).catch(() => "");
    const m = head.match(/^ref: refs\/heads\/(\S+)\s+HEAD/m);
    if (!m) return "main"; // not cached, so a later fix (token added, repo made) is picked up
    headCache.set(key, m[1]);
  }
  return headCache.get(key);
}

// Reads ?repo= and ?branch= (blank = the server's default repo/branch).
function target(url) {
  const rawRepo = url.searchParams.get("repo") || "";
  const repo = rawRepo ? parseRepo(rawRepo) : DEFAULT_REPO;
  if (!repo) return { error: `"${rawRepo.slice(0, 100)}" isn't a GitHub repo. Use owner/name.` };
  if (!repoAllowed(repo)) return { error: `${repo} isn't in this server's ALLOWED_REPOS.` };
  const branch = url.searchParams.get("branch") || "";
  if (branch && !validBranch(branch)) return { error: `"${branch.slice(0, 100)}" isn't a valid branch name.` };
  return { repo, branch };
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://x");

  if (url.pathname === "/" || url.pathname === "/healthz") {
    const d = mirrors.get(defaultKey);
    return send(res, 200, {
      ok: true, name: "livesync", multiRepo: true, startedAt: STARTED_AT, defaultRepo: DEFAULT_REPO, defaultBranch,
      version: d ? d.state.version : "", commit: d ? d.state.commit : null, error: d ? d.state.error : null,
      repos: mirrors.size,
    });
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
      let full = "";
      try { full = String(JSON.parse(body.toString("utf8")).repository.full_name || "").toLowerCase(); } catch {}
      for (const m of mirrors.values()) {
        if (!full || m.repo.toLowerCase() === full) {
          m.lastRemote = null;
          m.syncOnce(true);
        }
      }
      send(res, 200, { ok: true });
    });
    return;
  }

  if (!url.pathname.startsWith("/api/")) return send(res, 404, { error: "not found" });
  if (!keyOk(req)) {
    console.log(`401 wrong sync key from ${req.headers["x-forwarded-for"] || req.socket.remoteAddress}`);
    return send(res, 401, { error: "bad or missing X-Sync-Key" });
  }

  // Repos this server is mirroring right now, for the plugin's picker.
  if (url.pathname === "/api/repos" && req.method === "GET") {
    return send(res, 200, {
      defaultRepo: DEFAULT_REPO, defaultBranch, allowed: ALLOWED_REPOS,
      repos: [...mirrors.values()].sort((a, b) => b.lastUsed - a.lastUsed).map((m) => m.summary()),
    });
  }

  if (url.pathname === "/api/branches" && req.method === "GET") {
    const t = target(url);
    if (t.error) return send(res, 400, { error: t.error });
    fs.mkdirSync(WORKROOT, { recursive: true });
    listBranches(t.repo).then((r) => send(res, 200, r), (e) => send(res, 404, { error: e.message }));
    return;
  }

  if (url.pathname === "/api/state" && req.method === "GET") {
    const t = target(url);
    if (t.error) return send(res, 400, { error: t.error });
    if (!t.branch) {
      repoDefaultBranch(t.repo).then((b) => serveState(req, res, url, mirrorFor(t.repo, b)));
      return;
    }
    return serveState(req, res, url, mirrorFor(t.repo, t.branch));
  }

  send(res, 404, { error: "not found" });
});

// Long-poll: answers right away if the plugin is behind, else waits up to ?wait= seconds.
function serveState(req, res, url, m) {
  const since = String(url.searchParams.get("since") || "");
  const wait = Math.min(Number(url.searchParams.get("wait") || 0), 25);
  if (since !== m.state.version) {
    console.log(`[${m.key}] plugin sync: since=${since || "(none)"} -> ${m.state.version || "(loading)"}`);
  }
  const base = () => ({ repo: m.repo, branch: m.branch, version: m.state.version, commit: m.state.commit, error: m.state.error });
  const reply = () => {
    if (!m.state.version || since === m.state.version) {
      send(res, 200, Object.assign(base(), { unchanged: true, loading: !m.state.version && !m.state.error }));
    } else {
      send(res, 200, Object.assign(base(), { nodes: m.state.nodes, history: m.state.history, warnings: m.state.warnings }));
    }
  };
  const ready = m.state.version && since !== m.state.version;
  const failedFirst = !m.state.version && m.state.error;
  if (failedFirst && !since) return m.syncOnce(true).then(reply); // fresh connect: try again now
  if (ready || failedFirst || wait <= 0) return reply();
  let done = false;
  const fire = () => {
    if (done) return;
    done = true;
    clearTimeout(timer);
    m.lastUsed = Date.now();
    reply();
  };
  const timer = setTimeout(fire, wait * 1000);
  m.waiters.push(fire);
  req.on("close", () => {
    done = true;
    clearTimeout(timer);
  });
}

server.listen(PORT, () => console.log(`livesync listening on :${PORT}, default repo=${LOCAL_DIR || DEFAULT_REPO} branch=${defaultBranch}`));
mirrorFor(DEFAULT_REPO, defaultBranch);
setInterval(pollAll, POLL_SECONDS * 1000);
