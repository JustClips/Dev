# Playtest checklist

The build was checked with a simulated server run (fake Roblox runtime), the selene linter, a script that checks every UI path the controllers use, and a real Roblox server run (Luau execution) for model loading, rigging, animation loading and the tool grip. It has not been played in Studio yet, so the client side and anything visual still need a real playtest.

## Manual steps for Dev

1. **Enable API access in Studio:** Game Settings → Security → turn on *Enable Studio Access to API Services*. Without it, saves use an in-memory mock and are lost when you stop.
2. **Create the products:** make the 6 gamepasses and the dev products listed in `src/shared/Config/Products.luau` on the Creator Dashboard, then paste each ID into its `Id = 0` line. Until then those shop buttons stay hidden.
3. **Pull and play:** LiveSync pulls `main` into Studio. Press Play, run through the checklist below, then publish.

## Expected warnings

- `[DataService] ... Using an in-memory mock` when API access is off or the place is unpublished.
- `[ShopService] N products/gamepasses have no ID yet` until step 2 is done.
- `[WorldService] terrain built in X s` and `[AssetService] 65 models ready in X s` are normal info lines. If AssetService says some models failed, those show as simple placeholder shapes.

Anything else in Output (red errors especially) is a bug worth reporting.

## Checklist

### Look and feel (new)
- [ ] The map has terrain: grey moon ground, mountains around the hub, the Crater bowl, a purple Dark Side, red Mars, and a big Earth in the sky.
- [ ] Each of the 8 bases has an arch with the owner's name, a hatchery pad, a fenced green pet park with a habitat, a pond and trees.
- [ ] Your aliens walk around your park (walk animation), stop and idle, and do a happy jump now and then. Name and $/s float above them.
- [ ] The tool in your hand looks right (head on the ground in front of you while sweeping). The sweep arm animation plays.
- [ ] HUD: Base / Sell / Zones pills teleport you. Zones shows prices and locks. You can't teleport while carrying an egg.
- [ ] Shop, Index (3D aliens, silhouettes for missing ones), Rebirth and the hatch cutscene use the new stud style.

### First 2 minutes (the tutorial)
- [ ] You spawn on a base plot, holding a Toothbrush.
- [ ] Hold click / tap and drag over dust: tiles disappear, a puff plays, the backpack bar fills.
- [ ] The arrow points you somewhere useful at each step (dust → egg → base → rocket → shop).
- [ ] An egg appears within the first ~12 tiles. Walk into it to pick it up, and it shows above your head.
- [ ] Walk onto your base pad: the egg starts hatching (Common, 3 s), then the hatch cutscene plays.
- [ ] The alien appears in your pet park and income ticks up in the HUD.
- [ ] Walk onto the Rocket sell pad: the backpack empties and cash goes up.
- [ ] Shop → Tools → buy the Broom: the tool in your hand changes and sweeping covers more ground.

### Zones and tools
- [ ] Gates show their price. Pressing the prompt with enough cash opens the gate for you only.
- [ ] Locked zones can't be swept even if you jump the wall.
- [ ] Crater / Dark Side / Mars dust takes more hits and pays more.
- [ ] A vehicle tier (or the rental product) shows a Drive button. The vehicle drives, stays upright, sweeps a wide strip, and is removed when you jump out.

### Eggs, hatching, aliens
- [ ] Hatch timers count down on the base and keep counting after you rejoin.
- [ ] Filling all slots, then hatching a rarer egg, replaces your weakest alien.
- [ ] The Index screen lists found aliens and greys out the rest.
- [ ] Your top 3 aliens follow you around.

### Server events
- [ ] The Moon Clean % bar fills as the server sweeps. At 100% a Meteor Shower starts: the sky tints, meteors fall and drop eggs, then the Moon regrows.
- [ ] Server luck products show the luck banner for everyone.

### Monetization (after step 2)
- [ ] Each gamepass and product prompts, grants once, and still applies after rejoining.
- [ ] Gifting: choose a player in the shop, buy, and the gift arrives for them, not you.
- [ ] Offers never show before your first hatch and don't spam (3 min apart minimum).

### Persistence
- [ ] With API access on: cash, tools, aliens, zones, rebirths and hatches survive leaving and rejoining.
- [ ] After being away a few minutes, the Welcome Back screen shows offline income.

### Rebirth
- [ ] At the rebirth price, rebirthing resets cash, tools and zones, keeps aliens, and adds +50% cash.

## Not verified here

- Client UI and controllers in a real client (layouts were checked in an HTML preview only).
- Animation playback on screen (the tracks load on a real server, but that server doesn't step animations).
- LiveSync parsing every `.model.json` (world and GUI) correctly.
- Vehicle handling with the new bodies, terrain build time on a live server, prop placement by eye.
- StreamingEnabled behaviour on far-away zones.
- Real purchases and real DataStores.
- Luau strict type checking (`--!strict` is on, but it wasn't run through the Studio type checker).
