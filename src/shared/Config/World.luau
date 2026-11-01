--!strict
-- Map layout. Studs, Roblox axes. The hub runs along Z: a long dust field with the Rocket
-- in the middle and 4 bases on each side (like Steal an Egg). Zones continue north (-Z),
-- each behind a gated corridor.
--
--   z = -1208 .. -992 Europa Ice           (TileSize 6)
--   z = -992 .. -956  corridor + Gate_Europa
--   z = -956 .. -740  Mars Plains          (TileSize 6)
--   z = -740 .. -704  corridor + Gate_Mars
--   z = -704 .. -488  Dark Side            (TileSize 6)
--   z = -488 .. -452  corridor + Gate_DarkSide
--   z = -452 .. -232  Crater (floor y = -8) (TileSize 5)
--   z = -232 .. -196  corridor + Gate_Crater
--   z = -196 ..  186  Landing Site dust field, Rocket launch pad at the origin
--   z =  186 ..  198  South plaza: a paved strip with the big screen (leaves up to it)
--   bases at x = +-62..150 on both sides of the field, on raised stud platforms
--
-- Base local frame: -Z points at the field (the entrance), +X is the base's right.
-- tools/gen_world.py writes src/workspace/Moon from these numbers, so keep them in sync.

local World = {}

-- Max Z 186 since 2026-10-30: the plaza stalls went and the leaves reach the back wall.
World.Field = { Min = Vector2.new(-56, -196), Max = Vector2.new(56, 186) }
World.RocketPosition = Vector3.new(0, 0, 0)
World.RocketClearRadius = 15
World.LaunchPadRadius = 14
-- Leaf dumps on both sides of the market hall, facing out to the field. Walk or drive up to
-- one and your bag pours into it bit by bit (like making honey in Bee Swarm).
World.Dumps = {
	CFrame.lookAt(Vector3.new(-19, 0, 0), Vector3.new(-60, 0, 0)),
	CFrame.lookAt(Vector3.new(19, 0, 0), Vector3.new(60, 0, 0)),
}
World.DumpFront = 6.5 -- studs from a dump's centre to the middle of its standing spot
World.DumpRadius = 8 -- standing spot radius (cars count by their driver)
-- Every base also has a dump by its entrance (added below, after the base layout), so the
-- HUD's Base button takes you home and sells your bag in one tap (Dev, 2026-11-01). Its
-- standing spot is smaller so it fits between the arch and the Pet Trader.
World.BaseDumpRadius = 6
World.HubDumps = #World.Dumps -- dumps 1..HubDumps are the market hall's; the rest one per base

-- Standing spot radius of dump i.
function World.dumpRadius(i: number): number
	return if i > World.HubDumps then World.BaseDumpRadius else World.DumpRadius
end

-- Middle of dump i's standing spot.
function World.dumpSpot(i: number): Vector3
	return (World.Dumps[i] * CFrame.new(0, 0, -World.DumpFront)).Position
end

-- Index of base b's own dump in World.Dumps.
function World.baseDump(b: number): number
	return World.HubDumps + b
end

-- The dump closest to a position: index and standing spot. Only the market hall's dumps
-- and (with `baseIndex`) your own base's, never other players' bases.
function World.nearestDump(position: Vector3, baseIndex: number?): (number, Vector3)
	local best, bestSpot, bestD = 1, World.dumpSpot(1), math.huge
	for i in World.Dumps do
		if i > World.HubDumps and i ~= (if baseIndex and baseIndex > 0 then World.baseDump(baseIndex) else -1) then
			continue
		end
		local spot = World.dumpSpot(i)
		local d = (Vector3.new(spot.X, position.Y, spot.Z) - position).Magnitude
		if d < bestD then
			best, bestSpot, bestD = i, spot, d
		end
	end
	return best, bestSpot
end
World.Walkway = 6 -- paved strip between the dust field and the bases

-- South plaza: a paved strip along the hub's south wall with the big screen. The Garage
-- and Upgrade stalls that stood here were removed on 2026-10-30 (Dev: the HUD buttons do
-- the same), and the leaves now reach this strip.
World.Plaza = { Min = Vector2.new(-62, 186), Max = Vector2.new(62, 198) }
-- The Lucky Wheel stand in the middle of the plaza strip, in front of the big screen and
-- between the leaderboard stands, facing the field. Kept low (about 17 studs) so it only
-- covers the bottom edge of the screen. Keep x -11..11 clear of other stands.
-- (MapBuilder.luckyWheel; WheelController opens the window from its prompt.)
World.Wheel = CFrame.lookAt(Vector3.new(0, 0, 191), Vector3.new(0, 0, 0))
-- Global leaderboards (LeaderboardService): one stand each on the plaza strip in front of
-- the big screen, facing the field.
-- The Traveling Merchant's cart (MerchantService, Config/Merchant) in the middle of the
-- field, just north of the market hall and its leaf dumps (Dev, 2026-10-31; it stood on the
-- plaza strip at x 42 before, where the Time Played board is now). It faces north, away
-- from the hall, on a cobblestone path joined to the hall's round pad (MapBuilder). y 0.5
-- is the top of that pad and path.
World.Merchant = CFrame.lookAt(Vector3.new(0, 0.5, -26), Vector3.new(0, 0.5, -100))
World.MerchantPath = { Width = 14, FromZ = -12, ToZ = -32 } -- cobblestone strip under the cart
World.LeaderboardZ = 189
World.Leaderboards = {
	{ Key = "Earned", Title = "TOTAL CASH EARNED", Color = Color3.fromRGB(47, 191, 85), X = -42 },
	{ Key = "PerSec", Title = "BEST CASH / SEC", Color = Color3.fromRGB(255, 176, 32), X = -24 },
	{ Key = "Rebirths", Title = "MOST REBIRTHS", Color = Color3.fromRGB(155, 107, 255), X = 24 },
	{ Key = "Playtime", Title = "MOST TIME PLAYED", Color = Color3.fromRGB(60, 160, 255), X = 42 },
}

World.BaseCount = 8
World.BaseSize = Vector2.new(92, 88) -- width (local X), depth (local Z)
World.BaseInner = 62 -- distance from the hub centre line to a base's entrance edge
World.BaseFloorY = 1 -- bases sit on a 1-stud stud-plate platform
-- One colour per base: platform trim, corner lights and the name sign.
World.BaseColors = {
	Color3.fromRGB(76, 141, 255), -- blue
	Color3.fromRGB(255, 120, 60), -- orange
	Color3.fromRGB(61, 220, 90), -- green
	Color3.fromRGB(180, 110, 255), -- purple
	Color3.fromRGB(255, 200, 60), -- gold
	Color3.fromRGB(255, 90, 150), -- pink
	Color3.fromRGB(60, 210, 220), -- teal
	Color3.fromRGB(255, 77, 94), -- red
}

-- Where base i's Pet Trader stands, facing into the base.
function World.traderCFrame(i: number): CFrame
	return World.baseCFrame(i) * CFrame.new(World.Base.Trader) * CFrame.Angles(0, math.rad(90), 0)
end

-- Where base i's Quest Master stands (left side, mirroring the Pet Trader), facing into the base.
function World.questCFrame(i: number): CFrame
	return World.baseCFrame(i) * CFrame.new(World.Base.Quest) * CFrame.Angles(0, math.rad(-90), 0)
end

-- Zone quest NPCs (QuestService, Config/ZoneQuests): one just inside each zone, beside the
-- path from the gate, facing the people walking in. Y is the zone floor (the server
-- raycasts the real ground). The Backyard one stands by the Park gate.
World.ZoneNpc = {
	Landing = Vector3.new(16, 0, -186),
	Crater = Vector3.new(16, -8, -242),
	DarkSide = Vector3.new(16, 0, -496),
	Mars = Vector3.new(16, 0, -748),
	Europa = Vector3.new(16, 0, -1000),
} :: { [string]: Vector3 }

function World.zoneNpcCFrame(zoneId: string): CFrame?
	local at = World.ZoneNpc[zoneId]
	if not at then
		return nil
	end
	return CFrame.lookAt(at, at + Vector3.new(-1, 0, 1))
end

-- CFrame of base i on its platform floor, facing the field.
function World.baseCFrame(i: number): CFrame
	local side = if i <= 4 then -1 else 1
	local row = (i - 1) % 4
	local z = -147 + row * 98
	local x = side * (World.BaseInner + World.BaseSize.Y / 2)
	local pos = Vector3.new(x, World.BaseFloorY, z)
	return CFrame.lookAt(pos, Vector3.new(0, World.BaseFloorY, z))
end

-- Positions in the base local frame.
World.Base = {
	Arch = Vector3.new(0, 0, -42),
	Hatchery = Vector3.new(0, 0, -28),
	HatcheryRadius = 9,
	Spawn = Vector3.new(-18, 0, -31),
	SkinSign = Vector3.new(-16, 0, -38), -- the "Change Base" sign, clear of the arch, hatchery and every skin's decor
	Lamps = { Vector3.new(-40, 0, -40), Vector3.new(40, 0, -40) },
	Incubators = { Vector3.new(-13, 0, -24), Vector3.new(13, 0, -24) },
	-- The Pet Trader's stall (TraderService): the NPC stands here facing the path (-X).
	Trader = Vector3.new(31, 0, -28),
	-- The Quest Master's stall (QuestService), mirrored on the left side, facing +X.
	Quest = Vector3.new(-31, 0, -28),
	-- The base's leaf dump: right of the arch, in front of the Pet Trader, facing the path
	-- (-X). Its standing spot (World.BaseDumpRadius) ends at the front edge.
	Dump = Vector3.new(28, 0, -37.5),
	-- The fenced pet park. Pets wander inside it.
	ParkMin = Vector2.new(-42, -14),
	ParkMax = Vector2.new(42, 42),
	ParkGateWidth = 12,
	-- Props inside the park. Radius keeps wandering pets out of them; Size is the footprint
	-- (X by Z before Yaw) that eggs can't be placed on (trees: just the trunk).
	ParkProps = {
		{ Asset = "Base_PetHouse", Position = Vector3.new(-29, 0, 31), Yaw = -33, Radius = 10, Size = Vector2.new(14.5, 13), Scale = 1 },
		{ Asset = "Base_Pond", Position = Vector3.new(19, 0, 22), Yaw = 0, Radius = 7, Size = Vector2.new(16.4, 11.8), Scale = 1 },
		{ Asset = "Park_TreeRound", Position = Vector3.new(36, 0, -6), Yaw = 30, Radius = 3, Size = Vector2.new(3, 3), Scale = 1.3 },
		{ Asset = "Park_TreeTall", Position = Vector3.new(-37, 0, 2), Yaw = 80, Radius = 3, Size = Vector2.new(3, 3), Scale = 1.35 },
		{ Asset = "Park_TreeAutumn", Position = Vector3.new(4, 0, 37), Yaw = 140, Radius = 3, Size = Vector2.new(3, 3), Scale = 1.3 },
		{ Asset = "Park_Bench", Position = Vector3.new(-12, 0, 12), Yaw = 0, Radius = 3, Size = Vector2.new(3.6, 3.6), Scale = 1 },
		{ Asset = "Park_Rock1", Position = Vector3.new(34, 0, 35), Yaw = 60, Radius = 4, Size = Vector2.new(8.5, 7.4), Scale = 2.2 },
		{ Asset = "Park_FlowerBed", Position = Vector3.new(-40, 0, 38), Yaw = 10, Radius = 2, Size = Vector2.new(2.6, 3.1), Scale = 0.45 },
		{ Asset = "Park_Rock2", Position = Vector3.new(28, 0, 8), Yaw = 0, Radius = 2.5, Size = Vector2.new(5, 4.7), Scale = 2.2 },
	},
}

for b = 1, World.BaseCount do
	table.insert(World.Dumps, World.baseCFrame(b) * CFrame.new(World.Base.Dump) * CFrame.Angles(0, math.rad(90), 0))
end

-- Incubator spots on the hatchery pad (local to the hatchery centre): a ring of 8,
-- starting at the front (facing the field) and going round.
World.HatchSpots = {}
for i = 0, 7 do
	local a = math.pi + i * math.pi / 4
	table.insert(World.HatchSpots, Vector3.new(math.sin(a) * 5.6, 0, math.cos(a) * 5.6))
end

-- Corridors between zones, with the gate across the middle.
World.Corridors = {
	{ Zone = "Crater", Min = Vector2.new(-12, -232), Max = Vector2.new(12, -196), GateZ = -205, FromY = 0, ToY = -8 },
	{ Zone = "DarkSide", Min = Vector2.new(-12, -488), Max = Vector2.new(12, -452), GateZ = -479, FromY = -8, ToY = 0 },
	{ Zone = "Mars", Min = Vector2.new(-12, -740), Max = Vector2.new(12, -704), GateZ = -713, FromY = 0, ToY = 0 },
	{ Zone = "Europa", Min = Vector2.new(-12, -992), Max = Vector2.new(12, -956), GateZ = -965, FromY = 0, ToY = 0 },
}

-- Teleport targets for the HUD buttons (Base uses your own spawn).
World.Teleports = {
	Rocket = CFrame.lookAt(Vector3.new(-29, 4, 5), Vector3.new(-19, 4, 0)), -- on the west leaf dump's spot
	Crater = CFrame.lookAt(Vector3.new(0, -4, -240), Vector3.new(0, -4, -300)),
	DarkSide = CFrame.lookAt(Vector3.new(0, 4, -494), Vector3.new(0, 4, -560)),
	Mars = CFrame.lookAt(Vector3.new(0, 4, -746), Vector3.new(0, 4, -800)),
	Europa = CFrame.lookAt(Vector3.new(0, 4, -998), Vector3.new(0, 4, -1050)),
}

-- Terrain materials per area (colours are set at runtime).
World.TerrainColors = {
	Grass = Color3.fromRGB(104, 192, 72), -- backyard lawn, pet parks, hills
	LeafyGrass = Color3.fromRGB(86, 170, 62), -- park
	Sand = Color3.fromRGB(240, 216, 156), -- beach
	Sandstone = Color3.fromRGB(214, 180, 120), -- beach dunes
	Asphalt = Color3.fromRGB(84, 88, 96), -- city streets
	Snow = Color3.fromRGB(244, 248, 255), -- snowy peaks
	Glacier = Color3.fromRGB(196, 226, 246), -- snowy peaks hills
	Concrete = Color3.fromRGB(206, 210, 218), -- base floors, city
	Pavement = Color3.fromRGB(196, 186, 168), -- garden paths
	Rock = Color3.fromRGB(140, 136, 128), -- mountain tops
	Ground = Color3.fromRGB(150, 110, 72), -- dirt
}


return World
