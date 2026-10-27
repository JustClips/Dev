# GameDev

Source for the Roblox experience **GameDev**, with cloud live sync into Roblox Studio.

## How it works

1. Scripts live in `src/` using the Rojo file layout (mapping in `default.project.json`).
2. Anyone pushes to `main` on GitHub.
3. The **LiveSync server** (`sync-server/`, hosted on Railway) notices the new commit within a few seconds.
4. The **LiveSync Studio plugin** (`studio-plugin/`) is long-polling the server and applies the change to the open place. No reopening Studio.

Sync is one way: GitHub → Studio. Edits made by hand in Studio to synced scripts are overwritten on the next sync, so edit the files in the repo instead.

## File layout

| Repo path | In Studio |
|---|---|
| `src/shared/` | `ReplicatedStorage.Shared` |
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |

File rules (same as Rojo):

- `Name.server.luau` → Script, `Name.client.luau` → LocalScript, `Name.luau` → ModuleScript (`.lua` works too)
- a folder → Folder; a folder with `init.luau` / `init.server.luau` / `init.client.luau` becomes that script, with the other files as children
- `Name.txt` → StringValue

Because the layout is plain Rojo, `rojo serve` still works locally too.

## Install the Studio plugin

1. In Studio: **Plugins** tab → **Plugins Folder**.
2. Copy `studio-plugin/LiveSync.server.lua` into that folder and restart Studio (or reload plugins).
3. Click **LiveSync** in the Plugins tab, enter the server URL and sync key, press **Connect**.
4. The first time, Studio asks to allow HTTP requests to the server's domain. Allow it.

## Server

Railway settings live in `/railway.json` (it only redeploys when `sync-server/` or that file changes). `sync-server/server.js` is plain Node with no dependencies; it needs `git` (the Dockerfile installs it).

| Env var | Meaning |
|---|---|
| `SYNC_KEY` | required; the key the plugin sends as `X-Sync-Key` |
| `REPO_URL` | repo to mirror (default this repo) |
| `GITHUB_TOKEN` | read-only token if the repo is private (fine-grained, Contents: Read-only, this repo only) |
| `BRANCH` | default `main` |
| `POLL_SECONDS` | how often to check GitHub (default 3) |
| `WEBHOOK_SECRET` | optional; enables instant sync from a GitHub push webhook to `POST /webhook` |

Endpoints: `GET /healthz` (public), `GET /api/state?since=<version>&wait=<seconds>` (needs `X-Sync-Key`).

Run locally against this folder without git: `SYNC_KEY=dev LOCAL_DIR=$PWD node sync-server/server.js`
