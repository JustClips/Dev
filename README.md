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
| `src/gui/` | `StarterGui` |
| `src/workspace/` | `Workspace` |

File rules (Rojo-compatible):

- `Name.server.luau` → Script, `Name.client.luau` → LocalScript, `Name.luau` → ModuleScript (`.lua` works too)
- a folder → Folder; a folder with `init.luau` / `init.server.luau` / `init.client.luau` becomes that script, with the other files as children
- `Name.model.json` → any instance tree (Parts, UI, lights, constraints...)
- `init.meta.json` in a folder, or `Name.meta.json` next to a script, sets its `className`, `properties`, `attributes` and `tags`
- `Name.txt` → StringValue
- in `default.project.json`: `$className`, `$path`, `$properties`, `$attributes`, `$tags`

A `.model.json` looks like this:

```json
{
  "className": "Part",
  "properties": { "Anchored": true, "Size": [4, 1, 4], "Color": "#33AAFF", "Material": "Neon" },
  "attributes": { "Speed": 10, "Tint": { "Color3": [1, 0, 0] } },
  "tags": ["Lava"],
  "children": [{ "name": "Light", "className": "PointLight", "properties": { "Range": 12 } }]
}
```

Property values are read using the property's own type, so short forms work:
Vector3/Vector2 `[x, y, z]`, Color3 `[r, g, b]` (0–1 or 0–255) or `"#RRGGBB"`, UDim2 `[[xScale, xOffset], [yScale, yOffset]]`,
UDim `[scale, offset]`, enums by name (`"Neon"`), BrickColor by name, CFrame `{ "position": [..], "orientation": [deg, deg, deg] }`,
FontFace `{ "family": "rbxasset://...", "weight": "Bold" }`, NumberRange, NumberSequence, ColorSequence, Rect.
Rojo's explicit form (`{ "Vector3": [1, 2, 3] }`) also works and is required for non-basic attribute types.

What the plugin does on each sync: creates missing instances, updates changed properties/attributes/tags, resets
properties you removed from a file to their defaults, and deletes instances it created that are gone from the repo.
It never deletes things it didn't create. Warnings (unknown property, bad value) show in the panel and in Output.

## Install the Studio plugin

1. In Studio: **Plugins** tab → **Plugins Folder**.
2. Copy `studio-plugin/LiveSync.server.lua` into that folder and restart Studio (or reload plugins).
3. Click **LiveSync** in the Plugins tab, enter the server URL and sync key, press **Connect**. The login is saved and reconnects automatically next time; **Pause** stops syncing, **Log out** forgets the key.
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
