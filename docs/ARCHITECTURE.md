# Sweep the Moon for Alien Eggs: architecture

Design and numbers come from `GAME_PLAN.md` (project files, `game-ideas/sweep-the-moon/`). This doc covers how the code is put together.

## Layout

| Repo path | In Studio | What lives there |
|---|---|---|
| `src/shared/` | `ReplicatedStorage.Shared` | Configs, `BigNum`, `Format`, `Net`, `Grid`, `Types`, `Signal`, `AlienModel` |
| `src/server/` | `ServerScriptService.Server` | `Main` (boot), `Services/*`, `Lib/*` (ProfileStore, mock DataStore, touch helper) |
| `src/client/` | `StarterPlayerScripts.Client` | `Main` (boot), `State`, `Ui`, `Controllers/*` |
| `src/gui/` | `StarterGui` | Placeholder screens as `.model.json` (Hud, Shop, Index, Rebirth, Offer, WelcomeBack, Hatch) |
| `src/workspace/Moon/` | `Workspace.Moon` | Ground, walls, gates, rocket sell pad, 8 base plots, decor |
| `default.project.json` | | Also sets `Workspace.StreamingEnabled` and the Moon lighting + sky |

Dust tiles are not in the repo. `DustService` generates about 5,700 tiles at server start from the zone bounds in `Config/Zones.luau`.

## Boot

`Main.server.luau` creates every remote (`Net.setup()`), requires the services in a fixed order, calls every `Init(services)`, then every `Start()`. Services reach each other through the `services` table, so there are no require cycles. The client `Main.client.luau` does the same for controllers.

Players only get a character once their profile has loaded (`CharacterAutoLoads = false`), so nobody plays on unsaved default data. If the load fails, the player is kicked with a friendly message.

## Server services

| Service | Job |
|---|---|
| DataService | Session-locked profiles (`Lib/ProfileStore`): lock by token in `UpdateAsync`, steal after 30 min stale, autosave every 60 s, release on leave, `BindToClose` flush. Uses an in-memory mock in Studio when the place is unpublished or API access is off. Holds each player's `Session` (`Data` = saved, `Runtime` = this session only). |
| StateService | Sends each player one `PlayerState` snapshot (at most every 0.2 s) and owns `ReplicatedStorage.ServerState` attributes (Moon %, event, luck). Also works out the tutorial step. |
| AnalyticsService | Onboarding funnel (spawn → first sweep → sell → egg → hatch → tool → zone → rebirth), economy sources/sinks, custom offer events. |
| WorldService | Finds `Workspace.Moon`, builds slot markers and owner signs on the 8 base plots. |
| BaseService | Gives each player a base, spawns and respawns them there. |
| BoostService | Server luck tiers (time stacks per tier, highest active wins), personal 2x cash, and the single cash multiplier formula. |
| DustService | Tiles, HP, clearing, regrowth per zone, the Moon Clean counter, 0.1 s batches of cleared tile ids. |
| SweepService | Validates `SweepTick(position)`: rate (10/s token bucket), distance from the character, zone unlocked. Applies tool power through the grid lookup, fills the backpack, rolls eggs. |
| ToolService | Tool ladder, tool in hand, vehicle rentals, spawning the vehicle. |
| BackpackService | Dust units + their cash value, selling at the Rocket, `GiveCash` / `TrySpend` helpers. |
| ZoneService | Gate labels and ProximityPrompts, paid unlocks. |
| EggService | Egg chance per tile, guaranteed first egg (tile 12), physical eggs (owner-only for 15 s), carrying, delivering to your base pad. |
| HatchService | Hatch timers saved as unix `EndsAt` (they keep running offline), mutations, Skip Hatch. A higher-rarity egg on a full base replaces the weakest lower-rarity alien. |
| AlienService | Slot count, income every second, offline income on join, base visuals, the top-3 followers attribute. |
| RebirthService | Cost, reset, +50% cash per rebirth. |
| EventService | Meteor Shower state machine. |
| ShopService | Idempotent `ProcessReceipt`, gamepass checks, gifting, what each product grants. |
| OfferService | Contextual offers with cooldowns, never before the first hatch. |
| LeaderboardService | leaderstats and the overhead tag. |

## Remotes (`src/shared/Net.luau`)

Client → server (all rate limited): `SweepTick`, `OfferResponse`, `SetAutoSweep`, and the functions `GetState`, `BuyNextTool`, `Rebirth`, `PromptPurchase(key, giftToUserId?)`, `ToggleVehicle`, `EquipTool`.

Server → client: `PlayerState`, `TilesCleared` (buffer of u16 ids), `SweepResult`, `Notify`, `Announce`, `HatchCompleted`, `WelcomeBack`, `ShowOffer`, `MeteorImpact`.

The client never sends amounts. Every cash, egg and tool change happens on the server.

## Saved data (v1)

See `Types.ProfileData` and the template in `DataService`. Cash and TotalDust are `BigNum` tables (`{m, e}`), safe to store as-is. `ReceiptsGranted` maps purchase id → recipient user id, trimmed to the newest 100. To change the schema, bump `CURRENT_VERSION` and add a step to `MIGRATIONS`.

## How to add things

- **A tool:** add a row to `Config/Tools.luau` (keep tiers in order). For a Robux skip, add a `ToolSkipN` product in `Config/Products.luau`.
- **An alien:** add a row to `Config/Aliens.luau`. It joins its rarity's hatch pool and the index automatically.
- **A zone:** add a row to `Config/Zones.luau` with bounds that don't overlap others (keep total tiles under ~8k), add ground for it in `src/workspace/Moon/Ground.model.json`, and if it has a price add a part named `Gate_<ZoneId>` in `Gates.model.json` (ZoneService labels it and adds the prompt).
- **A product:** add it to `Config/Products.luau` with an existing `Kind`, or add a new `Kind` to `Types.ProductKind` plus a function in `GRANTS` in `ShopService`. Put it in a shop tab in `ShopController`.
- **New UI art:** edit the `.model.json` files in `src/gui`. Controllers only look up elements by name, so keep the names.

## Extension points (not built yet)

Egg stealing, trading, more planets, daily rewards, codes and group rewards. Base plots, eggs and hatching are already separate services, so stealing can hook into `EggService` and `HatchService` without touching the rest.
